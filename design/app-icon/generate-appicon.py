#!/usr/bin/env python3
"""Generate the Hoshidukiyo macOS AppIcon set from the CC0 owl source SVG.

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
ICONSET = os.path.join(REPO, "app", "Hoshidukiyo", "Assets.xcassets", "AppIcon.appiconset")

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
