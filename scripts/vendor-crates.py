#!/usr/bin/env python3
"""Vendor a Rust project's crates from its Cargo.lock, for an offline build in the Autark chroot.

Usage: vendor-crates.py <Cargo.lock> <out-dir>

Downloads every crates.io package the lock file names from static.crates.io, checks each against the sha256 the lock
file records, and unpacks it into <out-dir>/<name>-<version>/ with the .cargo-checksum.json cargo expects of a
directory source, listing every file's sha256 so cargo checks them at build time. Needs only Python 3 (no cargo),
so it runs on the host before Rust exists in Autark. Git dependencies are refused: they have no checksum in the lock
file.

The build then points cargo at <out-dir>, with --offline --locked:
    [source.crates-io]
    replace-with = "vendored"
    [source.vendored]
    directory = "<out-dir>"
"""
import hashlib
import json
import os
import sys
import tarfile
import tomllib
import urllib.request

REGISTRY = "registry+https://github.com/rust-lang/crates.io-index"


def file_sums(folder):
    sums = {}
    for root, _, files in os.walk(folder):
        for name in files:
            path = os.path.join(root, name)
            with open(path, "rb") as f:
                sums[os.path.relpath(path, folder)] = hashlib.sha256(f.read()).hexdigest()
    return sums


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip().splitlines()[2])
    lock, out = sys.argv[1], sys.argv[2]
    with open(lock, "rb") as f:
        packages = tomllib.load(f).get("package", [])
    os.makedirs(out, exist_ok=True)
    fetched = kept = 0
    for p in packages:
        source = p.get("source")
        if source is None:
            continue  # a workspace member
        name, version = p["name"], p["version"]
        if source != REGISTRY:
            sys.exit(f"{name} {version}: source {source} isn't crates.io; vendor it by hand")
        if "checksum" not in p:
            sys.exit(f"{name} {version}: no checksum in {lock}")
        folder = os.path.join(out, f"{name}-{version}")
        marker = os.path.join(folder, ".cargo-checksum.json")
        if os.path.exists(marker):
            with open(marker) as f:
                if json.load(f).get("package") == p["checksum"]:
                    kept += 1
                    continue
        url = f"https://static.crates.io/crates/{name}/{name}-{version}.crate"
        with urllib.request.urlopen(url, timeout=60) as r:
            data = r.read()
        got = hashlib.sha256(data).hexdigest()
        if got != p["checksum"]:
            sys.exit(f"{name} {version}: sha256 {got}, Cargo.lock says {p['checksum']}")
        crate = os.path.join(out, f".{name}-{version}.crate")
        with open(crate, "wb") as f:
            f.write(data)
        prefix = f"{name}-{version}/"
        with tarfile.open(crate) as t:
            for m in t.getmembers():
                # A .crate holds one top folder, <name>-<version>/; anything else is refused.
                if not (m.name + "/").startswith(prefix) or ".." in m.name.split("/"):
                    sys.exit(f"{name} {version}: unexpected path {m.name} in the .crate")
            t.extractall(out, filter="data")
        os.remove(crate)
        # Every file's sha256, as `cargo vendor` writes them: cargo checks them at each build, so a vendored folder
        # copied into Autark is verified there too.
        sums = file_sums(folder)
        with open(marker, "w") as f:
            json.dump({"files": sums, "package": p["checksum"]}, f)
        fetched += 1
    print(f"{fetched} crates fetched, {kept} already there, in {out}")


if __name__ == "__main__":
    main()
