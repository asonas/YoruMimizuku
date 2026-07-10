#!/usr/bin/env python3
"""Generate the iPad (iOS) AppIcon set for YoruMimizuku from the CC0 owl source.

iOS/iPadOS app icons must be FULL-BLEED and OPAQUE: no transparent margin, no
rounded corners, and — critically — no alpha channel at all (App Store rejects
alpha with ITMS-90717 "Invalid large app icon"). The OS applies its own rounded
mask. This differs from the macOS icon (see generate-appicon.py), which keeps a
margin, rounded corners, a shadow, and transparency.

Pipeline: owl-source-original.svg -> cleaned owl paths -> full-bleed opaque master
SVG (1024px, gradient fills the whole square) -> rasterized PNGs (all iPad sizes)
with the alpha channel stripped via ImageMagick.

Requires: python3, rsvg-convert (librsvg), ImageMagick (magick). Run from anywhere.
"""
import re
import os
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(HERE, "owl-source-original.svg")
MASTER = os.path.join(HERE, "AppIcon-ipad-master.svg")
ICONSET = os.path.join(REPO, "apps", "ipados", "Assets.xcassets", "AppIcon.appiconset")

CANVAS = 1024
# Owl scale on the full-bleed canvas. The owl art is centered on its bbox center
# (~44,53 in its 100x100 viewBox) and placed at the canvas center.
OWL_SCALE = 6.2
# The darkest background stop; used as the flatten color when dropping alpha (any
# antialiased edge pixels fall back to this rather than white).
FLATTEN_BG = "#0f1014"


def clean_owl_body(raw):
    """Strip Adobe Illustrator switch/foreignObject wrappers and namespaced attrs."""
    match = re.search(r"<switch>(.*?)</switch>", raw, flags=re.S)
    body = match.group(1) if match else raw
    body = re.sub(r"<foreignObject.*?</foreignObject>", "", body, flags=re.S)
    body = re.sub(r'\s+[a-zA-Z]+:[a-zA-Z]+="[^"]*"', "", body)
    return body.strip()


def build_master(owl_body):
    """Compose the full-bleed, opaque 1024px master SVG string."""
    owl = owl_body.replace('fill="#000000"', 'fill="url(#owl3)"')
    owl_placed = (
        f'<g transform="translate({CANVAS // 2},{CANVAS // 2}) '
        f'scale({OWL_SCALE}) translate(-44,-53)">' + owl + "</g>"
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
  <filter id="owlshadow" x="-40%" y="-40%" width="180%" height="180%">
    <feDropShadow dx="0" dy="12" stdDeviation="16" flood-color="#000" flood-opacity="0.45"/>
  </filter>
</defs>
<rect x="0" y="0" width="{CANVAS}" height="{CANVAS}" fill="url(#bg3)"/>
<g filter="url(#owlshadow)">{owl_placed}</g>
</svg>"""


# (filename, pixel size) for the iPad appiconset, matching Contents.json.
SIZES = [
    ("icon_ipad_20x20@1x.png", 20),
    ("icon_ipad_20x20@2x.png", 40),
    ("icon_ipad_29x29@1x.png", 29),
    ("icon_ipad_29x29@2x.png", 58),
    ("icon_ipad_40x40@1x.png", 40),
    ("icon_ipad_40x40@2x.png", 80),
    ("icon_ipad_76x76@1x.png", 76),
    ("icon_ipad_76x76@2x.png", 152),
    ("icon_ipad_83_5x83_5@2x.png", 167),
    ("icon_ios-marketing_1024x1024@1x.png", 1024),
]


def main():
    raw = open(SRC, encoding="utf-8", errors="ignore").read()
    master = build_master(clean_owl_body(raw))
    with open(MASTER, "w") as f:
        f.write(master)
    os.makedirs(ICONSET, exist_ok=True)
    for filename, px in SIZES:
        out = os.path.join(ICONSET, filename)
        # rsvg-convert always emits an RGBA PNG; render then drop the alpha channel
        # so the asset is fully opaque (RGB), which App Store validation requires.
        subprocess.run(
            ["rsvg-convert", "-w", str(px), "-h", str(px), "-o", out, MASTER],
            check=True,
        )
        subprocess.run(
            ["magick", out, "-background", FLATTEN_BG,
             "-alpha", "remove", "-alpha", "off", out],
            check=True,
        )
        print(f"rendered {filename} ({px}px, opaque)")


if __name__ == "__main__":
    main()
