import Foundation

// Maintenance CLI for docs/wiki. Subcommands:
//   wiki lint            validate frontmatter, [[links]], and source paths
//   wiki index           regenerate docs/wiki/index.md from page frontmatter
//   wiki index --check   fail if index.md is not up to date (no write)
//
// Run from the repo root. Foundation only, so it behaves the same on macOS and Windows.

let typeOrder = ["overview", "behavior", "platform", "meta"]
let sourcedTypes: Set<String> = ["overview", "behavior", "platform"]

struct Page {
    let relPath: String
    let basename: String
    let title: String?
    let type: String?
    let updated: String?
    let sources: [String]
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

// Minimal frontmatter parser: a leading `---` block of `key: value` lines, with a
// `sources:` list of subsequent `  - item` lines. Good enough for our own pages.
func parse(_ path: String) -> Page {
    let basename = (path as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
    let content = readNormalized(path)
    let lines = content.components(separatedBy: "\n")

    guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else {
        let body = content
        return Page(relPath: relativize(path), basename: basename, title: nil, type: nil,
                    updated: nil, sources: [], links: extractLinks(body), hasFrontmatter: false)
    }

    var title: String?, type: String?, updated: String?
    var sources: [String] = []
    var inSources = false
    for line in lines[1..<end] {
        if line.hasPrefix("- ") || line.hasPrefix("  - ") {
            if inSources {
                let item = line.drop(while: { $0 == " " }).dropFirst(2)
                sources.append(item.trimmingCharacters(in: .whitespaces))
            }
            continue
        }
        guard let colon = line.firstIndex(of: ":") else { continue }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        inSources = false
        switch key {
        case "title": title = value
        case "type": type = value
        case "updated": updated = value
        case "sources": inSources = true
        default: break
        }
    }

    let body = lines[(end + 1)...].joined(separator: "\n")
    return Page(relPath: relativize(path), basename: basename, title: title, type: type,
                updated: updated, sources: sources, links: extractLinks(body), hasFrontmatter: true)
}

let pages = markdownFiles(in: wikiDir).map(parse)
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

func runLint() {
    var errors: [String] = []

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
    }

    if errors.isEmpty {
        print("wiki: lint passed (\(listed.count) pages)")
    } else {
        fail("wiki: lint found \(errors.count) issue(s):\n" + errors.sorted().map { "  - " + $0 }.joined(separator: "\n"))
    }
}

func runIndex(check: Bool) {
    let generated = generateIndex()
    let indexPath = wikiDir + "/index.md"
    let current = readNormalized(indexPath)
    if check {
        if current == generated {
            print("wiki: index.md is up to date")
        } else {
            fail("wiki: index.md is stale — run `mise run wiki:index`")
        }
    } else {
        if current == generated {
            print("wiki: index.md already up to date")
        } else {
            try? generated.write(toFile: indexPath, atomically: true, encoding: .utf8)
            print("wiki: regenerated index.md")
        }
    }
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "lint":
    runLint()
case "index":
    runIndex(check: args.contains("--check"))
case "check":
    runLint()
    runIndex(check: true)
default:
    fail("usage: wiki <lint|index [--check]|check>")
}
