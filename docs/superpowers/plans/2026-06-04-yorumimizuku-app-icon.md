# YoruMimizuku App Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate the YoruMimizuku macOS app icon (a CC0 horned-owl "ミミズク" rendered in the app's dark + blue B3 style) and wire it into the Xcode project so the built app shows it.

**Architecture:** A reproducible pipeline. A CC0 owl SVG is stored as the source of truth under `design/app-icon/`. A Python script cleans the SVG, composes a 1024px "B3" master SVG (diagonal dark gradient background, blue top-lit owl, drop shadows, macOS rounded-square body with margin), and rasterizes every required macOS AppIcon size with `rsvg-convert` directly into `app/YoruMimizuku/Assets.xcassets/AppIcon.appiconset/`, writing a valid macOS `Contents.json`. `project.yml` gains `ASSETCATALOG_COMPILER_APPICON_NAME` so XcodeGen-generated project compiles the catalog as the app icon.

**Tech Stack:** Python 3, librsvg (`rsvg-convert`), XcodeGen, xcodebuild (macOS 14+).

**Working directory:** All paths are relative to the worktree root `/Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-icon` (branch `feature/app-icon`). Run all commands from there.

**Commit convention:** This repo commits via the `/commit` skill (`git ai-commit`) — never `git commit` directly. Each "Commit" step lists exactly which files to `git add`; create the commit through the `/commit` skill with the suggested message.

---

## File Structure

Files created or modified by this plan:

- Create `design/app-icon/owl-source-original.svg` — verbatim CC0 source SVG (provenance-preserving, never edited)
- Create `design/app-icon/SOURCE.md` — provenance + license record
- Create `design/app-icon/generate-appicon.py` — the generation script (single responsibility: source SVG → master SVG → appiconset PNGs + Contents.json)
- Create (generated) `design/app-icon/AppIcon-master.svg` — 1024px master, written by the script; committed for reference
- Create `app/YoruMimizuku/Assets.xcassets/Contents.json` — asset catalog root marker
- Create (generated) `app/YoruMimizuku/Assets.xcassets/AppIcon.appiconset/Contents.json` — icon set manifest
- Create (generated) `app/YoruMimizuku/Assets.xcassets/AppIcon.appiconset/icon_*.png` — 10 PNG entries
- Modify `project.yml` — add `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` under `settings.base`
- Modify `.gitignore` — ignore the throwaway `build/` derived-data directory used for verification

---

## Task 1: Store the CC0 source SVG and provenance

**Files:**
- Create: `design/app-icon/owl-source-original.svg`
- Create: `design/app-icon/SOURCE.md`

- [ ] **Step 1: Create the source SVG**

Create `design/app-icon/owl-source-original.svg` with EXACTLY this content (the verbatim CC0 asset; do not modify):

```xml
<svg xmlns:x="http://ns.adobe.com/Extensibility/1.0/" xmlns:i="http://ns.adobe.com/AdobeIllustrator/10.0/" xmlns:graph="http://ns.adobe.com/Graphs/1.0/" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" x="0px" y="0px" viewBox="0 0 100 100" enable-background="new 0 0 100 100" xml:space="preserve"><switch><foreignObject requiredExtensions="http://ns.adobe.com/AdobeIllustrator/10.0/" x="0" y="0" width="1" height="1"></foreignObject><g i:extraneous="self"><g><path fill-rule="evenodd" clip-rule="evenodd" fill="#000000" d="M55.835,84.216c9.414-7.483,15.992-17.259,19.976-30.173     c4.586-14.845,4.827-33.432,2.714-51.957c-2.714,2.776-5.671,7.301-8.508,10.802c-13.94,0-30.535,0-43.509,0     c-1.026-0.664-1.629-1.931-2.293-2.897C22.345,7.156,20.172,4.017,18.18,1C18.121,1,18.06,1,18,1c0,32.646,0,65.354,0,98     C22.042,98.397,43.042,93.206,55.835,84.216 M70.378,41.371C69.534,44.991,67.407,50,62.534,50C61,50,58,50,58,50s-5,0-5.483,0     c-2.08,0-4.517-5-5.009-5.311C47,45,45,49.879,42.982,50c0,0-10.982,0-12.07,0c-4.484,0-7.3-8.569-6.697-15.086     c0.965-10.319,10.742-13.578,20.819-14.361c12.25-0.846,25.646,3.197,26.009,15.628C71.102,38.293,70.681,40.104,70.378,41.371z"></path><path fill-rule="evenodd" clip-rule="evenodd" fill="#000000" d="M57.646,29.604c-3.621,0-6.578,2.957-6.578,6.577     c0,3.621,2.957,6.517,6.578,6.517c3.561,0,6.518-2.896,6.518-6.517C64.163,32.56,61.206,29.604,57.646,29.604z"></path><path fill-rule="evenodd" clip-rule="evenodd" fill="#000000" d="M36.524,29.604c-3.62,0-6.577,2.957-6.577,6.577     c0,3.621,2.957,6.517,6.577,6.517c3.621,0,6.517-2.896,6.517-6.517C43.042,32.56,40.146,29.604,36.524,29.604z"></path></g></g></switch></svg>
```

- [ ] **Step 2: Create the provenance record**

Create `design/app-icon/SOURCE.md`:

```markdown
# App Icon Source

- Asset: Owl (20398) - The Noun Project
- Source: Wikimedia Commons — https://commons.wikimedia.org/wiki/File:Owl_(20398)_-_The_Noun_Project.svg
- License: CC0 1.0 (public domain dedication). No attribution legally required; recorded here for traceability.
- File: `owl-source-original.svg` (verbatim, unmodified)
- Notes: The SVG ships with Adobe Illustrator `<switch>/<foreignObject>` wrappers and undefined-namespace
  attributes (`i:extraneous` etc.). `generate-appicon.py` strips these so standard renderers (librsvg) parse it.
- Motif: horned owl (ミミズク) — has 羽角 (ear tufts) at the crown, the trait distinguishing ミミズク from フクロウ.
```

- [ ] **Step 3: Verify the source SVG parses after cleaning**

Run this one-off check (does not write any output; just confirms librsvg can rasterize the cleaned source):

```bash
python3 - <<'PY'
import re, subprocess
raw = open("design/app-icon/owl-source-original.svg").read()
body = re.search(r"<switch>(.*?)</switch>", raw, flags=re.S).group(1)
body = re.sub(r"<foreignObject.*?</foreignObject>", "", body, flags=re.S)
body = re.sub(r'\s+[a-zA-Z]+:[a-zA-Z]+="[^"]*"', "", body)
svg = f'<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">{body}</svg>'
open("/tmp/_owl_check.svg","w").write(svg)
print(subprocess.run(["rsvg-convert","-w","64","-h","64","-o","/tmp/_owl_check.png","/tmp/_owl_check.svg"]).returncode)
PY
```

Expected: prints `0` (rsvg-convert exit code 0, meaning the cleaned SVG parsed and rasterized).

> Note: the `<<'PY'` heredoc above is a one-off verification check, not part of the committed pipeline. The reusable logic lives in the committed `generate-appicon.py` (Task 2). If your environment disallows inline heredocs, paste the body into a temp `.py` file and run that instead.

- [ ] **Step 4: Commit**

```bash
git add design/app-icon/owl-source-original.svg design/app-icon/SOURCE.md
```
Create the commit via the `/commit` skill. Suggested message: `Add CC0 owl source SVG and provenance for app icon`

---

## Task 2: Add the generation script and produce the icon set

**Files:**
- Create: `design/app-icon/generate-appicon.py`
- Create (generated): `design/app-icon/AppIcon-master.svg`
- Create (generated): `app/YoruMimizuku/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create (generated): `app/YoruMimizuku/Assets.xcassets/AppIcon.appiconset/icon_*.png` (10 files)

- [ ] **Step 1: Write the generation script**

Create `design/app-icon/generate-appicon.py` with exactly this content:

```python
#!/usr/bin/env python3
"""Generate the YoruMimizuku macOS AppIcon set from the CC0 owl source SVG.

Reproducible pipeline:
  owl-source-original.svg -> cleaned owl paths -> B3 master SVG (1024px)
  -> rasterized PNGs (all macOS sizes) + Contents.json in the appiconset.

Requires: python3, rsvg-convert (librsvg). Run from anywhere; paths are resolved
relative to this file.
"""
import re
import os
import json
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(HERE, "owl-source-original.svg")
MASTER = os.path.join(HERE, "AppIcon-master.svg")
ICONSET = os.path.join(REPO, "app", "YoruMimizuku", "Assets.xcassets", "AppIcon.appiconset")

CANVAS = 1024
MARGIN = 100
BODY = CANVAS - 2 * MARGIN  # 824
RADIUS = 185


def clean_owl_body(raw):
    """Strip Adobe Illustrator switch/foreignObject wrappers and namespaced attrs."""
    match = re.search(r"<switch>(.*?)</switch>", raw, flags=re.S)
    body = match.group(1) if match else raw
    body = re.sub(r"<foreignObject.*?</foreignObject>", "", body, flags=re.S)
    body = re.sub(r'\s+[a-zA-Z]+:[a-zA-Z]+="[^"]*"', "", body)
    return body.strip()


def build_master(owl_body):
    """Compose the 1024px B3 master SVG string."""
    owl = owl_body.replace('fill="#000000"', 'fill="url(#owl3)"')
    # owl art bbox center ~ (44,53) in its 100x100 viewBox; place centered in the body.
    owl_placed = (
        '<g transform="translate(512,540) scale(6.6) translate(-44,-53)">'
        + owl + "</g>"
    )
    return f"""<svg width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}" xmlns="http://www.w3.org/2000/svg">
<defs>
  <linearGradient id="bg3" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#222b40"/>
    <stop offset="0.55" stop-color="#171a22"/>
    <stop offset="1" stop-color="#0f1014"/>
  </linearGradient>
  <linearGradient id="owl3" x1="0.2" y1="0" x2="0.8" y2="1">
    <stop offset="0" stop-color="#bcd0fb"/>
    <stop offset="0.5" stop-color="#6f99f0"/>
    <stop offset="1" stop-color="#4a72d6"/>
  </linearGradient>
  <filter id="bodyshadow" x="-20%" y="-20%" width="140%" height="140%">
    <feDropShadow dx="0" dy="18" stdDeviation="22" flood-color="#000" flood-opacity="0.5"/>
  </filter>
  <filter id="owlshadow" x="-40%" y="-40%" width="180%" height="180%">
    <feDropShadow dx="0" dy="10" stdDeviation="14" flood-color="#000" flood-opacity="0.45"/>
  </filter>
  <clipPath id="bodyclip">
    <rect x="{MARGIN}" y="{MARGIN}" width="{BODY}" height="{BODY}" rx="{RADIUS}" ry="{RADIUS}"/>
  </clipPath>
</defs>
<rect x="{MARGIN}" y="{MARGIN}" width="{BODY}" height="{BODY}" rx="{RADIUS}" ry="{RADIUS}" fill="url(#bg3)" filter="url(#bodyshadow)"/>
<g clip-path="url(#bodyclip)">
  <g transform="translate({MARGIN},{MARGIN}) scale({BODY / 1024.0})">
    <g filter="url(#owlshadow)">{owl_placed}</g>
  </g>
</g>
</svg>"""


# (filename, pixel size). macOS uses pt sizes x scale; some pixel sizes repeat.
SIZES = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

CONTENTS = {
    "images": [
        {"idiom": "mac", "size": "16x16", "scale": "1x", "filename": "icon_16x16.png"},
        {"idiom": "mac", "size": "16x16", "scale": "2x", "filename": "icon_16x16@2x.png"},
        {"idiom": "mac", "size": "32x32", "scale": "1x", "filename": "icon_32x32.png"},
        {"idiom": "mac", "size": "32x32", "scale": "2x", "filename": "icon_32x32@2x.png"},
        {"idiom": "mac", "size": "128x128", "scale": "1x", "filename": "icon_128x128.png"},
        {"idiom": "mac", "size": "128x128", "scale": "2x", "filename": "icon_128x128@2x.png"},
        {"idiom": "mac", "size": "256x256", "scale": "1x", "filename": "icon_256x256.png"},
        {"idiom": "mac", "size": "256x256", "scale": "2x", "filename": "icon_256x256@2x.png"},
        {"idiom": "mac", "size": "512x512", "scale": "1x", "filename": "icon_512x512.png"},
        {"idiom": "mac", "size": "512x512", "scale": "2x", "filename": "icon_512x512@2x.png"},
    ],
    "info": {"version": 1, "author": "xcode"},
}


def main():
    raw = open(SRC, encoding="utf-8", errors="ignore").read()
    master = build_master(clean_owl_body(raw))
    with open(MASTER, "w") as f:
        f.write(master)
    os.makedirs(ICONSET, exist_ok=True)
    for filename, px in SIZES:
        out = os.path.join(ICONSET, filename)
        subprocess.run(
            ["rsvg-convert", "-w", str(px), "-h", str(px), "-o", out, MASTER],
            check=True,
        )
        print(f"rendered {filename} ({px}px)")
    with open(os.path.join(ICONSET, "Contents.json"), "w") as f:
        json.dump(CONTENTS, f, indent=2)
    print("wrote Contents.json")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run the generator**

Run: `python3 design/app-icon/generate-appicon.py`

Expected output (order may vary slightly):
```
rendered icon_16x16.png (16px)
rendered icon_16x16@2x.png (32px)
rendered icon_32x32.png (32px)
rendered icon_32x32@2x.png (64px)
rendered icon_128x128.png (128px)
rendered icon_128x128@2x.png (256px)
rendered icon_256x256.png (256px)
rendered icon_256x256@2x.png (512px)
rendered icon_512x512.png (512px)
rendered icon_512x512@2x.png (1024px)
wrote Contents.json
```

- [ ] **Step 3: Verify the outputs exist and have correct dimensions**

Run:
```bash
ls design/app-icon/AppIcon-master.svg
ls app/YoruMimizuku/Assets.xcassets/AppIcon.appiconset/
sips -g pixelWidth -g pixelHeight app/YoruMimizuku/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png
python3 -c "import json; d=json.load(open('app/YoruMimizuku/Assets.xcassets/AppIcon.appiconset/Contents.json')); print('entries:', len(d['images']))"
```

Expected:
- `AppIcon-master.svg` exists
- The appiconset directory lists 10 `icon_*.png` files + `Contents.json`
- `sips` reports `pixelWidth: 1024` and `pixelHeight: 1024` for `icon_512x512@2x.png`
- `entries: 10`

- [ ] **Step 4: Commit**

```bash
git add design/app-icon/generate-appicon.py design/app-icon/AppIcon-master.svg app/YoruMimizuku/Assets.xcassets/AppIcon.appiconset
```
Create the commit via the `/commit` skill. Suggested message: `Generate macOS AppIcon set from owl source`

---

## Task 3: Add the asset catalog root marker

**Files:**
- Create: `app/YoruMimizuku/Assets.xcassets/Contents.json`

- [ ] **Step 1: Create the catalog root Contents.json**

Create `app/YoruMimizuku/Assets.xcassets/Contents.json`:

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 2: Verify the catalog layout**

Run: `find app/YoruMimizuku/Assets.xcassets -maxdepth 2 -type f | sort`

Expected (12 files): the catalog `Contents.json`, the appiconset `Contents.json`, and the 10 `icon_*.png` files.

- [ ] **Step 3: Commit**

```bash
git add app/YoruMimizuku/Assets.xcassets/Contents.json
```
Create the commit via the `/commit` skill. Suggested message: `Add asset catalog root for YoruMimizuku`

---

## Task 4: Wire the icon into project.yml and regenerate the project

**Files:**
- Modify: `project.yml` (add one line under `settings.base`)
- Modify: `.gitignore` (ignore verification build dir)

- [ ] **Step 1: Add the AppIcon build setting**

In `project.yml`, under `targets.YoruMimizuku.settings.base` (the block that currently ends with `CODE_SIGN_STYLE: Automatic` on line 30), add one line so the block reads:

```yaml
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: as.ason.YoruMimizuku
        PRODUCT_NAME: YoruMimizuku
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: "1"
        SWIFT_VERSION: "6.0"
        ENABLE_HARDENED_RUNTIME: YES
        DEVELOPMENT_TEAM: QYP65434UW
        CODE_SIGN_STYLE: Automatic
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
```

- [ ] **Step 2: Ignore the verification build directory**

Append `build/` to `.gitignore` if not already present:

```bash
grep -qxF 'build/' .gitignore || printf 'build/\n' >> .gitignore
```

- [ ] **Step 3: Regenerate the Xcode project**

Run: `xcodegen generate --spec project.yml`

Expected: prints `Created project at .../YoruMimizuku.xcodeproj` (or `Loaded project ... Created project`), exit code 0.

- [ ] **Step 4: Verify the setting landed in the project**

Run: `grep -c ASSETCATALOG_COMPILER_APPICON_NAME YoruMimizuku.xcodeproj/project.pbxproj`

Expected: a number `>= 1` (the setting is present in the generated pbxproj).

- [ ] **Step 5: Commit**

```bash
git add project.yml .gitignore YoruMimizuku.xcodeproj/project.pbxproj
```
Create the commit via the `/commit` skill. Suggested message: `Set AppIcon for YoruMimizuku target`

> Note: if `YoruMimizuku.xcodeproj` is gitignored or not tracked in this repo, omit it from `git add` — XcodeGen regenerates it from `project.yml`. Check with `git check-ignore YoruMimizuku.xcodeproj/project.pbxproj` before adding.

---

## Task 5: Build and verify the icon is embedded

**Files:** none (verification only)

- [ ] **Step 1: Build the app**

Run:
```bash
xcodebuild build -project YoruMimizuku.xcodeproj -scheme YoruMimizuku -configuration Debug -derivedDataPath build/ CODE_SIGN_IDENTITY="-" 2>&1 | tail -20
```

Expected: ends with `** BUILD SUCCEEDED **`. If signing fails locally, the `CODE_SIGN_IDENTITY="-"` (ad-hoc) override should allow a Debug build; if it still fails on signing, add `CODE_SIGNING_ALLOWED=NO`.

- [ ] **Step 2: Confirm the asset catalog compiled into the bundle**

Run:
```bash
ls build/Build/Products/Debug/YoruMimizuku.app/Contents/Resources/Assets.car
```

Expected: the path exists (asset catalog, including AppIcon, was compiled by `actool`).

- [ ] **Step 3: Confirm `actool` recorded the AppIcon (no asset errors)**

Run:
```bash
xcrun --sdk macosx assetutil --info build/Build/Products/Debug/YoruMimizuku.app/Contents/Resources/Assets.car 2>/dev/null | grep -i -m1 "AppIcon\|Icon" || echo "check manually"
```

Expected: output references the AppIcon image set (the icon is present in the compiled catalog). If `assetutil` is unavailable, instead run `open build/Build/Products/Debug/YoruMimizuku.app` and visually confirm the Dock/Finder icon is the blue owl.

- [ ] **Step 4: Visual confirmation (human/agent eyes)**

Open the built app to confirm the Dock icon renders as the blue horned-owl on the dark rounded square:

```bash
open build/Build/Products/Debug/YoruMimizuku.app
```

Expected: the Dock shows the B3 owl icon. (Quit the app afterward.)

- [ ] **Step 5: No commit needed**

This task only verifies; `build/` is gitignored. If any verification failed, fix the relevant earlier task before proceeding.

---

## Task 6: Finish the branch

- [ ] **Step 1: Confirm a clean tree and review the log**

Run:
```bash
git status --short
git --no-pager log --oneline -6
```

Expected: working tree clean (only `build/` untracked, which is ignored); the recent commits include the four icon commits from Tasks 1–4.

- [ ] **Step 2: Hand off for integration**

Use the `superpowers:finishing-a-development-branch` skill to choose how to integrate `feature/app-icon` (merge to `main`, open a PR, etc.).

---

## Self-Review (completed by plan author)

**Spec coverage:**
- Store CC0 SVG + source/license + script under `design/app-icon/` → Tasks 1 & 2 ✓
- Generate B3 master 1024px SVG → Task 2 (`build_master`, writes `AppIcon-master.svg`) ✓
- Rasterize all macOS sizes (16,32,64,128,256,512,1024) via rsvg-convert into the appiconset → Task 2 `SIZES` ✓
- Valid macOS `Contents.json` → Task 2 `CONTENTS` (+ catalog root in Task 3) ✓
- Wire `ASSETCATALOG_COMPILER_APPICON_NAME` into `project.yml` + regenerate with XcodeGen → Task 4 ✓
- Verify the build shows the icon → Task 5 ✓

**Placeholder scan:** No TBD/TODO; every code/file step shows complete content. The one heredoc is explicitly marked as a one-off check with a non-heredoc fallback.

**Type/name consistency:** Filenames in `SIZES`, `CONTENTS`, and the verification `ls`/`sips` steps all match (`icon_<pt>x<pt>[@2x].png`). The setting name `ASSETCATALOG_COMPILER_APPICON_NAME` and value `AppIcon` match the appiconset directory name `AppIcon.appiconset`. Paths consistently rooted at the worktree.
