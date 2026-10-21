#!/usr/bin/env python3
"""Checks package recipes (scripts/pkg/*.sh) without building or running them.

    python3 -I scripts/ci/check-recipes.py [--strict FILE...]

Every recipe is checked for a well-formed header and bash syntax. Recipes named after --strict (the ones a pull
request adds or changes) must also use sha256 checksums and https sources, and a build() that downloads nothing. Exit status 1 if anything fails.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9+._-]*$")
ASSIGN = re.compile(r"^([a-z_]+)=(.*)$")
BUILD = re.compile(r"^build\s*\(\)")


def header(text):
    """The plain assignments before build(), as {key: raw value}; arrays may span lines."""
    out, lines, i = {}, text.splitlines(), 0
    while i < len(lines) and not BUILD.match(lines[i]):
        m = ASSIGN.match(lines[i])
        if m:
            key, val = m.group(1), m.group(2)
            if val.lstrip().startswith("(") and ")" not in val:
                while i + 1 < len(lines) and ")" not in lines[i]:
                    i += 1
                    val += " " + lines[i]
            out[key] = val.split("#")[0].strip() if not val.lstrip().startswith("(") else val
        i += 1
    return out


def words(raw):
    return re.findall(r"[^\s()]+", raw)


def check(path, strict):
    errs = []
    text = path.read_text()
    h = header(text)
    if h.get("name", "").strip("\"'") != path.stem:
        errs.append(f"name is {h.get('name')!r}, not the file name {path.stem!r}")
    if not NAME.match(path.stem):
        errs.append("name must be letters, digits and + . _ -")
    for key in ("version", "release", "source", "checksums"):
        if key not in h:
            errs.append(f"missing {key}=")
    if "release" in h and not h["release"].strip("\"'").isdigit():
        errs.append("release must be a whole number")
    if h.get("mode", "staged").strip("\"'") not in ("staged", "tracked"):
        errs.append("mode must be staged or tracked")
    src, sums = words(h.get("source", "")), words(h.get("checksums", ""))
    if len(src) != len(sums):
        errs.append(f"{len(src)} sources but {len(sums)} checksums")
    for s in src:
        if not re.match(r"^([^\s:]+::)?https?://", s):
            errs.append(f"source is not a URL: {s}")
        elif strict and "https://" not in s:
            errs.append(f"source must use https: {s}")
    for c in sums:
        if not re.match(r"^(md5|sha256):[0-9a-f]+$", c.strip("\"'")):
            errs.append(f"checksum must be md5:<hex> or sha256:<hex>: {c}")
        elif strict and not c.strip("\"'").startswith("sha256:"):
            errs.append(f"a new or changed recipe needs sha256, not {c.split(':')[0]}")
    if not any(BUILD.match(l) for l in text.splitlines()):
        errs.append("no build() function")
    if strict:
        body = text[text.find("build()"):]
        for pat, why in ((r"\b(curl|wget)\b", "build() must not download: list the source in source="),
                         (r"\|\s*(sudo\s+)?(ba|z)?sh\b", "build() must not pipe into a shell")):
            if re.search(pat, body):
                errs.append(why)
    r = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
    if r.returncode:
        errs.append("bash syntax: " + r.stderr.strip().splitlines()[-1])
    return errs


def main(argv):
    strict = {Path(a).name for a in argv[1:] if a != "--strict"}
    bad = 0
    recipes = sorted((ROOT / "scripts" / "pkg").glob("*.sh"))
    for p in recipes:
        if p.name in ("lib.sh", "acl-lib.sh") or p.name.startswith("_"):
            continue
        for e in check(p, p.name in strict):
            print(f"{p.relative_to(ROOT)}: {e}")
            bad += 1
    print(f"{len(recipes)} files checked, {bad} problems")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
