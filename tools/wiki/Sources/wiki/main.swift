import Foundation

// Maintenance CLI for docs/wiki. Subcommands:
//   wiki lint            validate frontmatter, [[links]], source paths, and feature blocks
//   wiki index           regenerate docs/wiki/index.md from page frontmatter
//   wiki index --check   fail if index.md is not up to date (no write)
//   wiki matrix          regenerate docs/wiki/support-matrix.md from behavior `features:` blocks
//   wiki matrix --check  fail if support-matrix.md is not up to date (no write)
//   wiki check           lint + verify index.md and support-matrix.md are up to date (CI / pre-commit)
//
// Run from the repo root. Foundation only, so it behaves the same on macOS and Windows.

let typeOrder = ["overview", "concept", "behavior", "platform", "matrix", "reference", "meta"]
let sourcedTypes: Set<String> = ["overview", "concept", "behavior", "platform"]

// Platform support matrix vocabulary. The `features:` frontmatter on each behavior
// page records a per-platform status; these map to the marks shown in the matrix.
let platforms = ["macos", "windows", "ios", "android"]
let statusSymbol: [String: String] = [
    "full": "○",      // supported, same behavior as the reference platform
    "differs": "△",   // supported but behaves differently per OS
    "limited": "△",   // partial implementation / limited UX
    "none": "×",      // not supported / not implemented
    "planned": "−",   // planned or out of scope for now
    "unknown": "?",   // not yet verified against the platform's app
]
// A status other than full/planned needs a `note` explaining why (the "理由を残す" rule).
let needsNoteStatuses: Set<String> = ["differs", "limited", "none", "unknown"]

struct Feature {
    var name: String = ""
    var statuses: [String: String] = [:]
    var note: String?
}

struct Page {
    let relPath: String
    let basename: String
    let title: String?
    let type: String?
    let updated: String?
    let sources: [String]
    let features: [Feature]
    let links: [String]
    let hasFrontmatter: Bool
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

// Read a file with line endings normalized to "\n". Windows checkouts may use
// CRLF, which would otherwise break the "---" frontmatter detection and make the
// index comparison always look stale; normalizing keeps the tool identical on
// macOS and Windows.
func readNormalized(_ path: String) -> String {
    let raw = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    return raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
}

let fm = FileManager.default
let root = fm.currentDirectoryPath
let wikiDir = root + "/docs/wiki"

guard fm.fileExists(atPath: wikiDir) else {
    fail("wiki: docs/wiki not found (run from the repo root)")
}

func relativize(_ path: String) -> String {
    let prefix = root + "/"
    let p = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    return p.replacingOccurrences(of: "\\", with: "/")
}

func markdownFiles(in dir: String) -> [String] {
    guard let en = fm.enumerator(atPath: dir) else { return [] }
    return en.compactMap { $0 as? String }
        .filter { $0.hasSuffix(".md") }
        .map { dir + "/" + $0 }
        .sorted()
}

func stripCode(_ body: String) -> String {
    // Drop fenced blocks and inline code so wikilinks shown as examples don't count as real links.
    let noFences = body.replacingOccurrences(
        of: "(?s)```.*?```", with: "", options: .regularExpression)
    return noFences.replacingOccurrences(
        of: "`[^`]*`", with: "", options: .regularExpression)
}

func extractLinks(_ body: String) -> [String] {
    guard let re = try? NSRegularExpression(pattern: "\\[\\[([^\\]\\|]+)\\]\\]") else { return [] }
    let text = stripCode(body)
    let ns = text as NSString
    return re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        .map { ns.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespaces) }
}

func unquote(_ s: String) -> String {
    if s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") {
        return String(s.dropFirst().dropLast())
    }
    return s
}

// Apply one `key: value` line to a feature (used for both the `- name:` item line
// and the indented attribute lines below it).
func applyFeatureField(_ feature: inout Feature, _ kv: String) {
    guard let colon = kv.firstIndex(of: ":") else { return }
    let key = kv[..<colon].trimmingCharacters(in: .whitespaces)
    let value = unquote(kv[kv.index(after: colon)...].trimmingCharacters(in: .whitespaces))
    switch key {
    case "name": feature.name = value
    case "note": feature.note = value
    case "macos", "windows", "ios", "android": feature.statuses[key] = value
    default: break
    }
}

// Minimal frontmatter parser: a leading `---` block of `key: value` lines, with a
// `sources:` list of `  - item` lines and a `features:` list of `  - name: ...`
// items each followed by 4-space-indented attribute lines. Good enough for our pages.
func parse(_ path: String) -> Page {
    let basename = (path as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
    let content = readNormalized(path)
    let lines = content.components(separatedBy: "\n")

    guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else {
        let body = content
        return Page(relPath: relativize(path), basename: basename, title: nil, type: nil,
                    updated: nil, sources: [], features: [], links: extractLinks(body),
                    hasFrontmatter: false)
    }

    var title: String?, type: String?, updated: String?
    var sources: [String] = []
    var features: [Feature] = []
    var block = ""  // "", "sources", or "features"

    for line in lines[1..<end] {
        // A feature item: "  - name: ..." (or any first key, by convention `name`).
        if block == "features", line.hasPrefix("  - ") {
            var feature = Feature()
            let kv = line.drop(while: { $0 == " " }).dropFirst(2)
            applyFeatureField(&feature, String(kv))
            features.append(feature)
            continue
        }
        // A feature attribute: a 4-space-indented "key: value" under the current item.
        if block == "features", line.hasPrefix("    "), !features.isEmpty {
            applyFeatureField(&features[features.count - 1], line.trimmingCharacters(in: .whitespaces))
            continue
        }
        // A sources item.
        if block == "sources", line.hasPrefix("- ") || line.hasPrefix("  - ") {
            let item = line.drop(while: { $0 == " " }).dropFirst(2)
            sources.append(item.trimmingCharacters(in: .whitespaces))
            continue
        }
        guard let colon = line.firstIndex(of: ":") else { continue }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        switch key {
        case "title": title = value; block = ""
        case "type": type = value; block = ""
        case "updated": updated = value; block = ""
        case "sources": block = "sources"
        case "features": block = "features"
        default: block = ""
        }
    }

    let body = lines[(end + 1)...].joined(separator: "\n")
    return Page(relPath: relativize(path), basename: basename, title: title, type: type,
                updated: updated, sources: sources, features: features,
                links: extractLinks(body), hasFrontmatter: true)
}

let pages = markdownFiles(in: wikiDir).map(parse)
// `index.md` and `log.md` are generated/log files excluded from the catalog. The
// generated `support-matrix.md` is kept in `listed` so it is linted and appears in
// the index like any other page.
let listed = pages.filter { $0.basename != "index" && $0.basename != "log" }
let knownBasenames = Set(pages.map { $0.basename })

func isISODate(_ s: String?) -> Bool {
    guard let s, s.count == 10 else { return false }
    let parts = s.split(separator: "-")
    return parts.count == 3 && parts[0].count == 4 && parts.allSatisfy { $0.allSatisfy(\.isNumber) }
}

func generateIndex() -> String {
    let maxUpdated = listed.compactMap { $0.updated }.max() ?? ""
    var out = "---\ntitle: Wiki Index\ntype: index\nupdated: \(maxUpdated)\nsources: []\n---\n\n"
    out += "# Wiki Index\n\n_Generated by `mise run wiki:index`. Do not edit by hand._\n"

    let groups = Dictionary(grouping: listed, by: { $0.type ?? "other" })
    let orderedTypes = typeOrder.filter { groups[$0] != nil }
        + groups.keys.filter { !typeOrder.contains($0) }.sorted()
    for type in orderedTypes {
        out += "\n## \(type)\n\n"
        for page in (groups[type] ?? []).sorted(by: { $0.basename < $1.basename }) {
            out += "- [[\(page.basename)]] — \(page.title ?? page.basename)\n"
        }
    }
    return out
}

func generateMatrix() -> String {
    let behaviorPages = listed.filter { $0.type == "behavior" }.sorted { $0.basename < $1.basename }
    let maxUpdated = behaviorPages.compactMap { $0.updated }.max()
        ?? (listed.compactMap { $0.updated }.max() ?? "")

    var out = "---\ntitle: Platform Support Matrix\ntype: matrix\nupdated: \(maxUpdated)\nsources: []\n---\n\n"
    out += "# Platform Support Matrix\n\n"
    out += "_Generated by `mise run wiki:matrix`. Do not edit by hand._\n\n"
    out += "At-a-glance support of each feature across platforms. It is generated from the "
    out += "`features:` frontmatter on the behavior pages, so to change a cell edit the source "
    out += "page (linked in each section heading), not this file.\n\n"
    out += "Legend: ○ supported (same behavior) · △ limited or OS-specific difference (see Notes) · "
    out += "× not supported · − planned / out of scope · ? unverified. "
    out += "Source statuses map as `full`→○, `differs`/`limited`→△, `none`→×, `planned`→−, `unknown`→?.\n"

    let header = "\n| Feature | macOS | Windows | iOS | Android |\n|---|:--:|:--:|:--:|:--:|\n"
    var notes: [String] = []
    for page in behaviorPages {
        out += "\n## [[\(page.basename)]] — \(page.title ?? page.basename)\n" + header
        for feature in page.features {
            let cells = platforms.map { statusSymbol[feature.statuses[$0] ?? ""] ?? "?" }
            out += "| \(feature.name) | \(cells[0]) | \(cells[1]) | \(cells[2]) | \(cells[3]) |\n"
            if let note = feature.note, !note.isEmpty {
                notes.append("- **\(feature.name)** ([[\(page.basename)]]): \(note)")
            }
        }
    }
    if !notes.isEmpty {
        out += "\n## Notes\n\nWhy a cell is limited (△), differs, unsupported (×), or unverified (?):\n\n"
        out += notes.joined(separator: "\n") + "\n"
    }
    return out
}

// All spec/plan ground-truth files that wiki pages are expected to derive from.
func groundTruthSources() -> [String] {
    ["docs/superpowers/specs", "docs/superpowers/plans"]
        .flatMap { markdownFiles(in: root + "/" + $0).map(relativize) }
        .sorted()
}

// Ground-truth specs/plans that no page lists in its `sources`. These are
// un-ingested: real, but not yet reflected in the wiki.
func uncitedSources() -> [String] {
    let cited = Set(pages.flatMap { $0.sources })
    return groundTruthSources().filter { !cited.contains($0) }
}

// Listed pages that no *other* page links to. The generated index links
// everything, so it is excluded as a link source; `overview` is the entry
// point and is exempt from being a link target.
func orphanPages() -> [String] {
    var inbound: Set<String> = []
    for page in listed {
        for link in page.links where link != page.basename {
            inbound.insert(link)
        }
    }
    let entryPoints: Set<String> = ["overview"]
    return listed
        .map { $0.basename }
        .filter { !entryPoints.contains($0) && !inbound.contains($0) }
        .sorted()
}

func runLint() {
    var errors: [String] = []
    var warnings: [String] = []

    let duplicates = Dictionary(grouping: pages, by: { $0.basename }).filter { $0.value.count > 1 }
    for (name, dupes) in duplicates {
        errors.append("duplicate basename '\(name)': \(dupes.map(\.relPath).joined(separator: ", "))")
    }

    for page in listed {
        let p = page.relPath
        guard page.hasFrontmatter else { errors.append("\(p): missing frontmatter"); continue }
        if page.title == nil { errors.append("\(p): missing 'title'") }
        if page.type == nil { errors.append("\(p): missing 'type'") }
        if !isISODate(page.updated) { errors.append("\(p): 'updated' must be YYYY-MM-DD") }
        if let t = page.type, sourcedTypes.contains(t), page.sources.isEmpty {
            errors.append("\(p): type '\(t)' requires at least one 'sources' entry")
        }
        for src in page.sources where !src.hasPrefix("http") {
            if !fm.fileExists(atPath: root + "/" + src) {
                errors.append("\(p): source not found: \(src)")
            }
        }
        for link in page.links where !knownBasenames.contains(link) {
            errors.append("\(p): unresolved wikilink [[\(link)]]")
        }

        // Behavior pages must declare a platform-support `features:` block so the
        // support matrix stays complete — adding/changing a behavior forces an update.
        if page.type == "behavior" {
            if page.features.isEmpty {
                errors.append("\(p): a 'behavior' page must declare at least one 'features:' entry (feeds the support matrix)")
            }
            for (i, feature) in page.features.enumerated() {
                let label = feature.name.isEmpty ? "feature[\(i)]" : "feature '\(feature.name)'"
                if feature.name.isEmpty {
                    errors.append("\(p): \(label): missing 'name'")
                }
                for plat in platforms {
                    guard let status = feature.statuses[plat] else {
                        errors.append("\(p): \(label): missing status for '\(plat)'")
                        continue
                    }
                    if statusSymbol[status] == nil {
                        errors.append("\(p): \(label): invalid status '\(status)' for '\(plat)' (use full/differs/limited/none/planned/unknown)")
                    }
                }
                let flagged = platforms.contains { needsNoteStatuses.contains(feature.statuses[$0] ?? "") }
                if flagged, (feature.note ?? "").isEmpty {
                    errors.append("\(p): \(label): a differs/limited/none/unknown status requires a 'note' explaining why")
                }
            }
        }
    }

    // Coverage and reachability are advisory: they surface gaps without blocking a
    // commit, so a freshly-added spec (not yet ingested) does not fail the build.
    for src in uncitedSources() {
        warnings.append("uncited source (no page derives from it): \(src)")
    }
    for orphan in orphanPages() {
        warnings.append("orphan page (no inbound [[link]]): \(orphan)")
    }

    if !warnings.isEmpty {
        print("wiki: \(warnings.count) warning(s):\n" + warnings.sorted().map { "  - " + $0 }.joined(separator: "\n"))
    }
    if errors.isEmpty {
        print("wiki: lint passed (\(listed.count) pages)")
    } else {
        fail("wiki: lint found \(errors.count) issue(s):\n" + errors.sorted().map { "  - " + $0 }.joined(separator: "\n"))
    }
}

func runGenerated(name: String, task: String, generate: () -> String, check: Bool) {
    let generated = generate()
    let path = wikiDir + "/" + name
    let current = readNormalized(path)
    if check {
        if current == generated {
            print("wiki: \(name) is up to date")
        } else {
            fail("wiki: \(name) is stale — run `mise run wiki:\(task)`")
        }
    } else {
        if current == generated {
            print("wiki: \(name) already up to date")
        } else {
            try? generated.write(toFile: path, atomically: true, encoding: .utf8)
            print("wiki: regenerated \(name)")
        }
    }
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "lint":
    runLint()
case "index":
    runGenerated(name: "index.md", task: "index", generate: generateIndex, check: args.contains("--check"))
case "matrix":
    runGenerated(name: "support-matrix.md", task: "matrix", generate: generateMatrix, check: args.contains("--check"))
case "check":
    runLint()
    runGenerated(name: "support-matrix.md", task: "matrix", generate: generateMatrix, check: true)
    runGenerated(name: "index.md", task: "index", generate: generateIndex, check: true)
default:
    fail("usage: wiki <lint|index [--check]|matrix [--check]|check>")
}
