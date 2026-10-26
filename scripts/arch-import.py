#!/usr/bin/env python3
"""arch-import.py: turn Arch Linux package recipes (PKGBUILDs) into autark-pkg recipes.

    python3 -I scripts/arch-import.py [--out DIR] [--recipes DIR] [-r] <package>...

For each package it
  - finds the PKGBUILD in Arch's packaging repository (gitlab.archlinux.org), pinned to the commit it read;
  - downloads every source, checks it against the hash the PKGBUILD gives, and records its sha256 (autark-pkg
    takes md5 and sha256 only); a `git+https://github.com/o/r#tag=X` source becomes GitHub's (or GitLab's) tag
    archive, which has no hash to check against, so it is pinned by the sha256 first seen;
  - maps the dependencies to Autark's recipes (scripts/pkg/arch-names.map), importing missing ones with -r;
  - writes `<out>/<name>.sh`: a recipe whose build() unpacks the sources as makepkg would, then runs the
    PKGBUILD's own prepare(), build() and package() with $srcdir and $pkgdir set. check() is not run.

The PKGBUILD is run through bash once to read its arrays and functions (top-level code only; build steps run later,
under autark-pkg, as the unprivileged build user). Only read official-repository PKGBUILDs this way.

Not handled yet, and reported: git sources from other hosts or without a tag or commit, git submodules,
install scripts (*.install), split packages' per-package depends, and dependencies nobody provides.
"""

import argparse
import datetime
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request

GITLAB = "https://gitlab.archlinux.org"
PACKAGES = "archlinux/packaging/packages"
ARCH_API = "https://archlinux.org/packages/search/json/"
AGENT = {"User-Agent": "autark-arch-import/0.1"}
ARCHIVE = re.compile(r"\.(tar|tar\.\w+|tgz|tbz2|txz|zip)$")
DRIVER_UNPACKS = re.compile(r"\.(tar\.\w+|tgz|tbz2)$")  # autark-pkg unpacks the first source when it is one of these
SIGNATURE = re.compile(r"\.(sig|asc|sign)$")
HASHES = [
    ("sha256sums", lambda: hashlib.sha256()),
    ("sha512sums", lambda: hashlib.sha512()),
    ("b2sums", lambda: hashlib.blake2b(digest_size=64)),
    ("sha384sums", lambda: hashlib.sha384()),
    ("sha224sums", lambda: hashlib.sha224()),
    ("sha1sums", lambda: hashlib.sha1()),
    ("md5sums", lambda: hashlib.md5()),
]
METADATA = ["pkgbase", "pkgname", "pkgver", "pkgrel", "epoch", "pkgdesc", "arch", "depends", "makedepends", "provides",
            "source", "noextract", "options", "install", "validpgpkeys", "license", "url", "backup", "groups", "replaces",
            "conflicts", "optdepends", "checkdepends", "changelog"] + [name for name, _ in HASHES]

# Prints the PKGBUILD's metadata, the variables it defines beyond those, and its functions, NUL separated.
READER = r"""
cd "$1"
CARCH=x86_64
before=$(compgen -v | sort)
source ./PKGBUILD >/dev/null
after=$(compgen -v | sort)
for v in $METADATA; do
  declare -p "$v" >/dev/null 2>&1 || continue
  if [[ $(declare -p "$v") == "declare -a"* ]]; then
    printf 'A\0%s\0' "$v"; eval 'for x in "${'"$v"'[@]}"; do printf "%s\0" "$x"; done'; printf 'Z\0'
  else
    printf 'S\0%s\0%s\0' "$v" "${!v}"
  fi
done
for v in $(comm -13 <(echo "$before") <(echo "$after")); do
  case " $METADATA " in *" $v "*) continue ;; esac
  case $v in before|after|v|x|BASH_*|_) continue ;; esac
  printf 'D\0%s\0' "$(declare -p "$v")"
done
for f in $(declare -F | sed 's/^declare -f //'); do
  printf 'F\0%s\0%s\0' "$f" "$(declare -f "$f")"
done
"""


def http(url, binary=True):
    request = urllib.request.Request(url, headers=AGENT)
    try:
        with urllib.request.urlopen(request, timeout=60) as reply:
            data = reply.read()
    except urllib.error.HTTPError as err:
        raise SystemExit(f"{url}: HTTP {err.code}" + (" (Arch has no such page)" if err.code == 404 else ""))
    except urllib.error.URLError as err:
        raise SystemExit(f"{url}: {err.reason}")
    return data if binary else data.decode()


def download(url, cache):
    """The file at url, in the cache folder (named by the hash of the url), and its path."""
    os.makedirs(cache, exist_ok=True)
    path = os.path.join(cache, hashlib.sha256(url.encode()).hexdigest())
    if not os.path.exists(path):
        temporary = path + ".part"
        with open(temporary, "wb") as out:
            out.write(http(url))
        os.rename(temporary, path)
    return path


def file_hash(path, make):
    digest = make()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def arch_package(name):
    """Arch's own record of a package (pkgbase, version, repo), or None."""
    reply = json.loads(http(ARCH_API + "?" + urllib.parse.urlencode({"name": name}), binary=False))
    for entry in reply["results"]:
        if entry["arch"] in ("x86_64", "any"):
            return entry
    return None


def packaging_commit(pkgbase):
    project = urllib.parse.quote(f"{PACKAGES}/{pkgbase}", safe="")
    return json.loads(http(f"{GITLAB}/api/v4/projects/{project}/repository/commits/main", binary=False))["id"]


def packaging_repository(info):
    """The packaging repository's name for a package, from the link on its page at archlinux.org: a few were renamed
    there (tree's is unix-tree) while the package search still says the old pkgbase."""
    page = http(f"https://archlinux.org/packages/{info['repo']}/{info['arch']}/{info['pkgname']}/", binary=False)
    found = re.search(re.escape(f"{GITLAB}/{PACKAGES}/") + r'([^"/]+)"', page)
    return found.group(1) if found else info["pkgbase"]


def packaging_raw(pkgbase, commit, path):
    return f"{GITLAB}/{PACKAGES}/{pkgbase}/-/raw/{commit}/{urllib.parse.quote(path)}"


def read_pkgbuild(directory):
    """The PKGBUILD in the folder, evaluated: {'meta': {name: str|list}, 'vars': [declarations], 'funcs': {name: text}}."""
    env = {"PATH": "/usr/bin:/bin", "HOME": "/nonexistent", "METADATA": " ".join(METADATA)}
    run = subprocess.run(["bash", "--noprofile", "--norc", "-c", READER, "reader", directory], env=env,
                         capture_output=True, check=False)
    if run.returncode != 0:
        raise SystemExit(f"the PKGBUILD did not evaluate: {run.stderr.decode(errors='replace')[:400]}")
    fields = run.stdout.split(b"\0")
    meta, variables, functions = {}, [], {}
    i = 0
    while i < len(fields) - 1:
        kind = fields[i].decode()
        if kind == "S":
            meta[fields[i + 1].decode()] = fields[i + 2].decode()
            i += 3
        elif kind == "A":
            key, values, i = fields[i + 1].decode(), [], i + 2
            while fields[i] != b"Z":
                values.append(fields[i].decode())
                i += 1
            meta[key] = values
            i += 1
        elif kind == "D":
            variables.append(fields[i + 1].decode())
            i += 2
        elif kind == "F":
            functions[fields[i + 1].decode()] = fields[i + 2].decode()
            i += 3
        else:
            i += 1
    return {"meta": meta, "vars": variables, "funcs": functions}


def as_list(value):
    return value if isinstance(value, list) else ([value] if value else [])


def load_overrides(directory, name):
    """Deliberate differences from Arch, one file per package: `drop <dependency>` and `sub <old> => <new>` (a text
    replacement in the PKGBUILD's functions, which must match something, so an update that moves it is noticed)."""
    drops, subs = [], []
    for stem in ("_all", name):  # _all.map: drops that apply to every package
        path = os.path.join(directory, f"{stem}.map")
        if not os.path.exists(path):
            continue
        for line in open(path):
            line = line.rstrip("\n")
            if line.startswith("drop "):
                drops.append(line[5:].strip())
            elif line.startswith("sub ") and " => " in line and stem == name:
                old, new = line[4:].split(" => ", 1)
                subs.append((old, new))
    return drops, subs


def load_names(path):
    """`archname autarkname` per line; `archname -` means "nothing to depend on" (provided outside autark-pkg)."""
    names = {}
    if os.path.exists(path):
        for line in open(path):
            line = line.split("#")[0].split()
            if len(line) == 2:
                names[line[0]] = line[1]
    return names


class Importer:
    def __init__(self, args):
        self.args = args
        self.names = load_names(args.names)
        self.known = {f[:-3] for d in (args.recipes, args.out) if os.path.isdir(d) for f in os.listdir(d) if f.endswith(".sh")}
        self.done = set()
        self.report = []

    def dependency(self, dep, notes, depth, runtime=True):
        """The autark recipe name for an Arch dependency, or None. A missing build-time one is imported only with --make-deps."""
        dep = re.split(r"[<>=]", dep)[0]
        if ".so" in dep:  # a soname: the package that has it is in the list too
            return None
        dep = self.names.get(dep, dep)
        if dep == "-":
            return None
        if dep in self.known:
            return dep
        if self.args.recursive and (runtime or self.args.make_deps) and depth < self.args.depth and dep not in self.done:
            try:
                self.convert(dep, depth + 1)
            except SystemExit as err:
                notes.append(f"dependency {dep}: {err}")
                return None
            if dep in self.known:
                return dep
        notes.append(f"dependency {dep}: no recipe (left out)")
        return None

    def commit_patches(self, functions, meta, notes):
        """prepare() often runs `git cherry-pick -n <sha>` or `git show <sha> -- file | git apply -`; a source archive has no
        history, so each commit becomes a patch fetched from the upstream host (a source, pinned by its sha256) and applied
        with patch(1) or git apply. `git apply -3` needs a repository too, and means a plain apply here."""
        picks = {}
        texts = {}
        for key, text in functions.items():
            for sha in re.findall(r"git cherry-pick -n ([0-9a-f]{40})", text) + re.findall(r"git show ([0-9a-f]{40}) -- \S+ \| git apply -", text):
                picks[sha] = f"commit-{sha[:12]}.patch"
            text = re.sub(r"git cherry-pick -n ([0-9a-f]{40})", lambda m: f'patch -Np1 -i "$srcdir/commit-{m.group(1)[:12]}.patch"', text)
            text = re.sub(r"git show ([0-9a-f]{40}) -- (\S+) \| git apply -",
                          lambda m: f'git apply --include={m.group(2)} < "$srcdir/commit-{m.group(1)[:12]}.patch"', text)
            text = re.sub(r"git apply (?:-3|--3way)\b", "git apply", text)
            texts[key] = text
        if not picks:
            return texts, []
        upstream = None
        for entry in as_list(meta.get("source")):
            git = re.match(r"(?:[^:]*::)?git\+(https://[^#?]+?)(?:\.git)?(?:[?#].*)?$", entry)
            if git:
                upstream = urllib.parse.urlparse(git.group(1))
                break
        if upstream is None or len(upstream.path.strip("/").split("/")) < 2:
            raise SystemExit("prepare() cherry-picks commits, and no git source says where they come from")
        extra = []
        for sha, file in picks.items():
            if upstream.netloc == "github.com":
                url = f"https://github.com{upstream.path}/commit/{sha}.patch"
            elif upstream.netloc.startswith("gitlab."):
                url = f"https://{upstream.netloc}{upstream.path}/-/commit/{sha}.patch"
            elif upstream.netloc == "codeberg.org":
                url = f"https://codeberg.org{upstream.path}/commit/{sha}.patch"
            else:
                raise SystemExit(f"prepare() cherry-picks commit {sha[:12]}, and git host {upstream.netloc} is not supported")
            extra.append((file, url))
            notes.append(f"commit {sha[:12]} fetched as a patch ({file}) instead of git cherry-pick; pinned by the sha256 first seen")
        return texts, extra

    def sources(self, meta, pkgbase, commit, notes):
        """[(file name, url, sha256, unpacked-as folder or None)] for the PKGBUILD's sources."""
        entries = [s for s in as_list(meta.get("source")) if not SIGNATURE.search(s.split("::")[-1].split("#")[0])]
        original = as_list(meta.get("source"))
        wanted = {}
        for name, _ in HASHES:
            values = as_list(meta.get(name))
            if len(values) == len(original):
                wanted = {"algorithm": name, "values": dict(zip(original, values))}
                break
        out = []
        for entry in entries:
            fixed_name, _, rest = entry.partition("::") if "::" in entry else ("", "", entry)
            clone = None
            git = re.match(r"git\+(https://[^#?]+?)(?:\.git)?(?:\?[^#]*)?(?:#(tag|commit|branch)=(.+))?$", rest)
            checked = True
            if git:
                base, kind, ref = git.groups()
                ref = re.sub(r"\?(un)?signed$", "", ref or "")  # Arch's marker that the tag is checked with gpg; not part of the name
                host = urllib.parse.urlparse(base)
                parts = host.path.strip("/").split("/")
                repo = parts[-1]
                clone = fixed_name or repo
                if kind not in ("tag", "commit"):
                    notes.append(f"source {entry}: git source without a tag or commit (not pinned)")
                    raise SystemExit("; ".join(notes))
                if host.netloc == "github.com" and len(parts) == 2:
                    url = f"{base}/archive/{ref}.tar.gz"
                elif host.netloc.startswith("gitlab.") and len(parts) >= 2:
                    url = f"{base}/-/archive/{ref}/{repo}-{ref}.tar.gz"
                elif host.netloc == "codeberg.org" and len(parts) == 2:
                    url = f"{base}/archive/{ref}.tar.gz"
                else:
                    notes.append(f"source {entry}: git host {host.netloc} is not supported")
                    raise SystemExit("; ".join(notes))
                file = f"{repo}-{ref}.tar.gz"
                checked = False
                notes.append(f"source {file}: pinned by the sha256 first seen: Arch pins {kind} {ref} of the git repository, "
                             f"which has no file hash to check")
            elif "://" in rest:
                url, file = rest, fixed_name or rest.rsplit("/", 1)[-1].split("?")[0]
            else:  # a file kept in the packaging repository (a patch, a config)
                url, file = packaging_raw(pkgbase, commit, rest), fixed_name or rest
            path = download(url, self.args.cache)
            if checked and wanted:
                expected = wanted["values"].get(entry, "SKIP")
                if expected != "SKIP":
                    make = dict(HASHES)[wanted["algorithm"]]
                    if file_hash(path, make) != expected:
                        raise SystemExit(f"{file}: {wanted['algorithm']} does not match the PKGBUILD's")
                else:
                    notes.append(f"source {file}: the PKGBUILD gives no hash (SKIP); pinned by the sha256 first seen")
            elif checked:
                notes.append(f"source {file}: the PKGBUILD gives no usable hash; pinned by the sha256 first seen")
            out.append((file, url, file_hash(path, hashlib.sha256), clone))
        return out

    def convert(self, name, depth=0):
        info = arch_package(name)
        if not info:
            raise SystemExit(f"{name}: not in Arch's repositories")
        pkgbase = info["pkgbase"]
        try:
            commit = packaging_commit(pkgbase)
        except SystemExit:
            pkgbase = packaging_repository(info)
            commit = packaging_commit(pkgbase)
        notes = []
        with tempfile.TemporaryDirectory() as work:
            with open(os.path.join(work, "PKGBUILD"), "wb") as out:
                out.write(http(packaging_raw(pkgbase, commit, "PKGBUILD")))
            pkg = read_pkgbuild(work)
        meta, functions = pkg["meta"], pkg["funcs"]
        pkgnames = as_list(meta.get("pkgname"))
        if name not in pkgnames:
            raise SystemExit(f"{name}: not one of the PKGBUILD's packages {pkgnames}")
        if len(pkgnames) > 1:
            notes.append(f"split package ({' '.join(pkgnames)}): only package_{name}() is run, and depends are its own, or the shared ones")
        package_function = f"package_{name}" if f"package_{name}" in functions else "package"
        if package_function not in functions:
            raise SystemExit(f"{name}: no {package_function}() in the PKGBUILD")
        if meta.get("install"):
            notes.append(f"install script {meta['install']} is ignored (its hooks do not run)")
        if "submodule" in "".join(functions.values()):
            notes.append("the build uses git submodules: a source archive has none")
        drops, subs = load_overrides(self.args.overrides, name)
        for old, new in subs:
            if not any(old in text for text in functions.values()):
                raise SystemExit(f"override `{old}` matches nothing in the PKGBUILD any more: look at {name}.map")
            functions = {key: text.replace(old, new) for key, text in functions.items()}
            notes.append(f"override: `{old}` replaced by `{new}`")
        functions, patches = self.commit_patches(functions, meta, notes)
        sources = self.sources(meta, pkgbase, commit, notes)
        for file, url in patches:
            sources.append((file, url, file_hash(download(url, self.args.cache), hashlib.sha256), None))
        depends = []
        runtime = as_list(meta.get("depends"))
        # makepkg lets package_x() set its own depends (or add to the shared ones), which is what keeps libcups from needing ghostscript
        for assign, values in re.findall(r"^\s*depends(\+?)=\(([^)]*)\)", functions.get(package_function, ""), re.M):
            own = shlex.split(values)
            runtime = runtime + own if assign else own
        for dep in runtime + [d for d in as_list(meta.get("makedepends")) if d not in runtime]:
            if re.split(r"[<>=]", dep)[0] in drops:
                notes.append(f"override: dependency {dep} dropped")
                continue
            found = self.dependency(dep, notes, depth, runtime=dep in runtime)
            if found and found != name and found not in depends:
                depends.append(found)
        version = meta["pkgver"].replace(":", "_")
        release = int(re.match(r"\d+", meta.get("pkgrel", "1")).group(0))
        description = re.sub(r'["$`\\]', "", meta.get("pkgdesc", ""))
        render = lambda number: self.render(name, pkgbase, commit, version, number, description, sources, depends, pkg,
                                            functions, package_function, meta, notes)
        text = render(release)
        # A recipe rewritten with other contents under the same version must not reuse the build kept for the old
        # one (autark-pkg keys builds on version-release), so its release goes up.
        target = os.path.join(self.args.out, f"{name}.sh")
        if os.path.exists(target):
            old = open(target).read()
            old_version = re.search(r"^version=(.*)$", old, re.M)
            old_release = re.search(r"^release=(\d+)$", old, re.M)
            if old_version and old_release and old_version.group(1) == version:
                number = int(old_release.group(1))
                undated = lambda text: re.sub(r"on \d{4}-\d\d-\d\d", "", text)
                if undated(render(number)) == undated(old):
                    text, release = old, number
                else:
                    release = max(release, number + 1)
                    text = render(release)
        os.makedirs(self.args.out, exist_ok=True)
        with open(target, "w") as out:
            out.write(text)
        self.known.add(name)
        self.done.add(name)
        self.report.append((name, version, notes))
        print(f"{'  ' * depth}{name} {version}-{release}: {len(sources)} sources, depends {' '.join(depends) or '-'}")
        for note in notes:
            print(f"{'  ' * depth}  ! {note}")

    def render(self, name, pkgbase, commit, version, release, description, sources, depends, pkg, functions,
               package_function, meta, notes):
        lines = [
            f"# {name} {version}: imported from Arch Linux's packaging repository ({pkgbase}, commit {commit[:12]}) by",
            f"# scripts/arch-import.py on {datetime.date.today()}. IMPORTED from Arch; delete this line to take the recipe over by hand.",
        ]
        lines += [f"# NOTE: {note}" for note in notes]
        lines += [
            f"name={name}",
            f"version={version}",
            f"release={release}",
            f'description="{description}"',
            "source=(" + "\n  ".join([""] + [f"{file}::{url}" for file, url, _, _ in sources]) + "\n)" if sources else "source=()",
            "checksums=(" + "\n  ".join([""] + [f"sha256:{digest}" for _, _, digest, _ in sources]) + "\n)" if sources else "checksums=()",
            f"depends=({' '.join(depends)})",
            "mode=staged",
            "",
        ]
        noextract = set(as_list(meta.get("noextract")))
        first = (as_list(meta.get("pkgname")) or [name])[0]
        body = ['build() {', '  cd "$srcdir"', "  # makepkg unpacks every archive source into $srcdir (autark-pkg already unpacked the first .tar.*)"]
        for index, (file, _, _, clone) in enumerate(sources):
            if not ARCHIVE.search(file) or file in noextract or (index == 0 and DRIVER_UNPACKS.search(file)):
                continue
            body.append(f'  bsdtar -xf "$srcdir/{file}"')
        for file, _, _, clone in sources:
            if clone:  # a git source is a folder named for the clone; a tag archive's folder is named otherwise
                body.append(f'  top=$(tar -tf "$srcdir/{file}" | sed -n \'1{{s|^\\./||;s|/.*||;p}}\')')
                body.append(f'  [ -e "{clone}" ] || mv "$top" "{clone}"')
        if sources:  # makepkg keeps the downloaded files in the folder above $srcdir too, and some PKGBUILDs read "../file.patch"
            body.append("  ln -sf " + " ".join(f'"$srcdir/{file}"' for file, _, _, _ in sources) + ' "$srcdir/.."')
        body += [
            "  set +u  # PKGBUILDs assume makepkg's environment, where CPPFLAGS, RUSTFLAGS and the like always exist",
            "  startdir=$srcdir pkgdir=$DESTDIR CARCH=x86_64 CHOST=x86_64-pc-linux-gnu",
            "  unset DESTDIR  # makepkg does not set it, and a Makefile given both it and prefix=$pkgdir/usr installs under it twice",
            # makepkg runs prepare() and build() with pkgname the first package of a split PKGBUILD, and package_x() with x
            f"  pkgname={first} pkgbase={pkgbase} pkgver={meta['pkgver']} pkgrel={meta.get('pkgrel', '1')}",
        ]
        for declaration in pkg["vars"]:
            body.append("  " + declaration.replace("\n", "\n  "))
        body.append("")
        # Functions the PKGBUILD defines for its own use (_srcenv, _pick) are called by prepare(), build() and package().
        own = {key: text for key, text in functions.items()
               if key not in ("prepare", "build", "check", "pkgver", package_function) and not key.startswith("package_")}
        for text in own.values():
            body.append(re.sub(r"^", "  ", text, flags=re.M))
        # Arch's devtools install arch-meson, a meson setup with the distribution's options; PKGBUILDs call it as a command.
        if any("arch-meson" in text for text in functions.values()):
            body.append("  arch-meson () { meson setup --prefix /usr --libexecdir lib --sbindir bin --buildtype plain "
                        "--auto-features enabled --wrap-mode nodownload -D b_pie=true \"$@\"; }")
        called = []
        for arch_name, as_name in (("prepare", "arch_prepare"), ("build", "arch_build"), (package_function, "arch_package")):
            if arch_name not in functions:
                continue
            text = re.sub(r"^\S+ \(\)", f"{as_name} ()", functions[arch_name], count=1)
            if "-m build" in text and "--skip-dependency-check" not in text:
                # build checks the version pins of the PEP 517 backends (flit_core<4) against our versions, which differ from Arch's
                text = text.replace("--no-isolation", "--no-isolation --skip-dependency-check")
            body.append(re.sub(r"^", "  ", text, flags=re.M))
            called.append(as_name)
        body.append("")
        for as_name in called:
            body.append(f'  cd "$srcdir"; {"pkgname=" + name + "; " if as_name == "arch_package" and first != name else ""}{as_name}')
        # What makepkg removes after package(): its PURGE_TARGETS (usr/share/info/dir is one index every info package would
        # otherwise own, and perllocal.pod and .packlist are Perl's install logs) and, unless the PKGBUILD keeps them, .la files.
        body.append("  # makepkg's purge step: files that would make this package conflict with others")
        body.append('  find "$pkgdir" -type f \\( -path "*/usr/share/info/dir" -o -path "*/usr/info/dir" -o -name .packlist -o -name "*.pod" \\) -delete')
        if "libtool" not in as_list(meta.get("options")):
            body.append('  find "$pkgdir" -type f -name "*.la" -delete')
        body.append("}")
        return "\n".join(lines) + "\n" + "\n".join(body) + "\n"


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description="Import Arch Linux packages as autark-pkg recipes.")
    parser.add_argument("packages", nargs="+")
    parser.add_argument("--out", default=os.path.join(here, "pkg-arch"), help="where the recipes are written")
    parser.add_argument("--recipes", default=os.path.join(here, "pkg"), help="Autark's own recipes (dependencies found there are used)")
    parser.add_argument("--names", default=os.path.join(here, "pkg", "arch-names.map"))
    parser.add_argument("--overrides", default=os.path.join(here, "arch-overrides"), help="per-package differences from Arch")
    parser.add_argument("--cache", default=os.path.expanduser("~/.cache/autark-arch-import"))
    parser.add_argument("-r", "--recursive", action="store_true", help="import missing dependencies too")
    parser.add_argument("--make-deps", action="store_true", help="with -r, import missing build-time dependencies too (many more packages)")
    parser.add_argument("--depth", type=int, default=3)
    args = parser.parse_args()
    importer = Importer(args)
    failed = 0
    for name in args.packages:
        try:
            importer.convert(name)
        except SystemExit as err:
            print(f"{name}: {err}", file=sys.stderr)
            failed += 1
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
