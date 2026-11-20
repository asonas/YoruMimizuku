"""Checks design/icons against Lucide's icon conventions: the exact root <svg>
attributes in order, only plain shape elements with position and size
attributes, coordinates inside the 1px safe zone, kebab-case names, and a
metadata file with the required keys and categories from Lucide's
icon.schema.json. Two things Lucide's own icons use beyond the written
conventions are allowed: `ry` on <rect> (image) and fill="currentColor" on a
dot <circle> (palette).

Usage: python3 tools/icons/lint.py [design/icons]
"""
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT_ATTRS = [
    ("xmlns", "http://www.w3.org/2000/svg"), ("width", "24"), ("height", "24"),
    ("viewBox", "0 0 24 24"), ("fill", "none"), ("stroke", "currentColor"),
    ("stroke-width", "2"), ("stroke-linecap", "round"), ("stroke-linejoin", "round"),
]
ALLOWED = {
    "path": {"d"}, "line": {"x1", "y1", "x2", "y2"}, "polyline": {"points"},
    "polygon": {"points"}, "circle": {"cx", "cy", "r"}, "ellipse": {"cx", "cy", "rx", "ry"},
    "rect": {"x", "y", "width", "height", "rx", "ry"},
}
# Allowed only on these elements and only with this value: Lucide's palette
# fills its dots.
FIXED = {"circle": {"fill": "currentColor"}}
CATEGORIES = {
    "accessibility", "account", "ai", "animals", "arrows", "buildings", "charts", "communication",
    "connectivity", "cursors", "design", "development", "devices", "education", "emoji", "files",
    "finance", "food-beverage", "gaming", "home", "layout", "letters-digits", "logistics", "mail",
    "math", "medical", "multimedia", "nature", "navigation", "notifications", "people", "photography",
    "science", "security", "shapes", "shopping", "social", "sports", "sustainability", "text", "time",
    "tools", "transportation", "travel", "weather",
}
REQUIRED_META = {"$schema", "contributors", "categories", "tags", "use-cases"}
# Lucide's metadata schema, pinned to the revision the categories above
# were taken from, so editors can validate against the same list.
SCHEMA = ("https://raw.githubusercontent.com/lucide-icons/lucide/"
          "d79f7054831776702c2f0e6b795069750f0a4f28/icon.schema.json")
NAME = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
# Stroke centers must stay 2 units from the edge: the stroke's half width (1)
# plus Lucide's 1px padding.
LOW, HIGH = 2.0, 22.0


def check_bounds(tag, attrs, problems, name):
    def within(v):
        return LOW - 1e-6 <= v <= HIGH + 1e-6

    numbers = []
    if tag == "line":
        numbers = [float(attrs[k]) for k in ("x1", "y1", "x2", "y2")]
    elif tag in ("polyline", "polygon"):
        numbers = [float(n) for n in re.split(r"[\s,]+", attrs["points"].strip())]
    elif tag == "circle":
        cx, cy, r = (float(attrs[k]) for k in ("cx", "cy", "r"))
        numbers = [cx - r, cx + r, cy - r, cy + r]
    elif tag == "ellipse":
        cx, cy, rx, ry = (float(attrs[k]) for k in ("cx", "cy", "rx", "ry"))
        numbers = [cx - rx, cx + rx, cy - ry, cy + ry]
    elif tag == "rect":
        x, y, w, h = (float(attrs[k]) for k in ("x", "y", "width", "height"))
        numbers = [x, x + w, y, y + h]
    for value in numbers:
        if not within(value):
            problems.append(f"{name}: <{tag}> reaches {value}, outside the safe zone {LOW}-{HIGH}")
            return


def lint(directory):
    problems = []
    svgs = sorted(directory.glob("*.svg"))
    for svg in svgs:
        name = svg.stem
        if not NAME.match(name):
            problems.append(f"{name}: name is not kebab-case")
        text = svg.read_text()
        opening = re.match(r"\s*<svg\s([^>]*)>", text)
        attrs = ([(k, v) for k, _, v in re.findall(r"""([\w:-]+)\s*=\s*(["'])(.*?)\2""", opening.group(1))]
                 if opening else [])
        if attrs != ROOT_ATTRS:
            problems.append(f"{name}: root attributes differ from {ROOT_ATTRS}")
        root = ET.fromstring(text)
        for child in root:
            tag = child.tag.split("}")[-1]
            if tag not in ALLOWED:
                problems.append(f"{name}: <{tag}> is not allowed")
                continue
            if len(child):
                problems.append(f"{name}: <{tag}> must not contain other elements")
            fixed = FIXED.get(tag, {})
            extra = {k for k in child.attrib
                     if k not in ALLOWED[tag] and child.attrib[k] != fixed.get(k)}
            if extra:
                problems.append(f"{name}: <{tag}> has disallowed attributes {sorted(extra)}")
            else:
                check_bounds(tag, child.attrib, problems, name)
        meta_path = svg.with_suffix(".json")
        if not meta_path.exists():
            problems.append(f"{name}: missing {meta_path.name}")
            continue
        meta = json.loads(meta_path.read_text())
        missing = REQUIRED_META - set(meta)
        if missing:
            problems.append(f"{name}: metadata lacks {sorted(missing)}")
        if "$schema" in meta and meta["$schema"] != SCHEMA:
            problems.append(f"{name}: $schema should be {SCHEMA}")
        # "$extends:<icon>" inherits the categories of another Lucide icon.
        unknown = {c for c in meta.get("categories", [])
                   if not (c.startswith("$extends:") and NAME.match(c[len("$extends:"):]))} - CATEGORIES
        if unknown:
            problems.append(f"{name}: unknown categories {sorted(unknown)}")
        if not meta.get("tags") or not meta.get("contributors"):
            problems.append(f"{name}: tags and contributors need at least one entry")
    for meta_path in directory.glob("*.json"):
        if not meta_path.with_suffix(".svg").exists():
            problems.append(f"{meta_path.stem}: metadata without an icon")
    return svgs, problems


if __name__ == "__main__":
    directory = Path(sys.argv[1] if len(sys.argv) > 1 else "design/icons")
    svgs, problems = lint(directory)
    for problem in problems:
        print(problem)
    print(f"icons: {len(svgs)} checked, {len(problems)} problem(s)")
    sys.exit(1 if problems else 0)
