import re, sys, os
d, wl, out = sys.argv[1:]
urls = [l.strip().rsplit('/',1)[1] for l in open(wl) if l.strip()]
tars = [u for u in urls if re.search(r'\.(tar\.(xz|gz|bz2)|tgz)$', u)]
pages = [p[:-5] for p in open(os.path.join(d,'pages.txt')).read().split()]
SKIP_PAGES = {'pkgmgt','aboutdebug','grub'}
NOSRC = {'stripping','cleanup'}
TARBALL = {'libelf':'elfutils-0.195.tar.bz2','sqlite':'sqlite-autoconf-3530400.tar.gz','tcl':'tcl8.6.18-src.tar.gz'}
def tarball(p):
    if p in TARBALL: return TARBALL[p]
    n = {'flit-core':'flit_core'}.get(p,p)
    m = [t for t in tars if re.match(re.escape(n)+r'[-_]?v?[0-9]', t, re.I) and '-doc' not in t and 'man-pages-2' not in t]
    if p == 'systemd': m = [t for t in m if 'man-pages' not in t]
    assert len(m) == 1, (p, m); return m[0]
SKIP = {
 'glibc': ['rm -f /usr/sbin/nscd','systemctl disable --now nscd','make localedata/install-locales','tzselect'],
 'readline': ['install -v -m644 doc/'], 'tcl': ['cd ..'], 'gmp': ['ABI=32'], 'libxcrypt': ['make distclean'],
 'shadow': ['passwd root'], 'gawk': ['install -vDm644 doc/'], 'ncurses': ['cp -v -R doc','make distclean'],
 'bash': ['exec /usr/bin/bash'], 'expat': ['install -v -m644 doc/'], 'openssl': ['cp -vfr doc/'],
 'sqlite': ['cp -v -R sqlite-doc'], 'Python': ['install -v -dm755 /usr/share/doc/python'],
 'iproute2': ['install -vDm644 COPYING'], 'kbd': ['cp -R -v docs/doc'], 'texinfo': ['make TEXMF','pushd /usr/share/info'],
 'vim': ["vim -c ':options'"], 'util-linux': ['bash tests/run.sh'], 'e2fsprogs': ['makeinfo -o',"sed 's/metadata_csum_seed"],
}
REPLACE = {  # (page, old, new): each must match exactly once
 ('glibc','             --enable-stack-protector=strong \\\n','             --enable-stack-protector=strong \\\n             --enable-fortify-source=3       \\\n'),
 ('glibc','localedef -i zh_TW -f UTF-8 zh_TW.UTF-8','localedef -i zh_TW -f UTF-8 zh_TW.UTF-8\nlocaledef -i en_PH -f UTF-8 en_PH.UTF-8'),
 ('glibc','/usr/share/zoneinfo/<xxx>','/usr/share/zoneinfo/Asia/Manila'),
 ('libffi','--with-gcc-arch=native','--with-gcc-arch=x86-64-v3'),
 ('groff','PAGE=<paper_size>','PAGE=letter'),
 ('gmp',"cat $(find -name '*.log') | grep -c ^PASS","n=$(cat $(find -name '*.log') | grep -c ^PASS); echo \"GMP tests passed: $n (need >= 199)\"; [ \"$n\" -ge 199 ]"),
 ('stripping','* ) strip --strip-unneeded $i','* ) strip --strip-unneeded $i 2>/dev/null || true  # book: non-ELF files error, ignore'),
}
FATAL_TESTS = {'gmp','mpfr'}   # book: critical, all must pass
DIAG = ['grep "Timed out"', "grep '^FAIL:'", '../contrib/test_summary']
TEST_RE = re.compile(r'\b(make|ninja)\b[^\n]*\b(check|test|tests|check-root|check_local|test_harness)\b')
EXTRA_AFTER = {'vim': "{\ngrep -q 'FAILED: 0' vim-test.log\n} || testfail \"vim: vim-test.log has no 'FAILED: 0'\"",
               'mpfr': "grep -E '^# (PASS|FAIL):' tests/test-suite.log; grep -q '^# FAIL: *0$' tests/test-suite.log"}
used = set(); fns = []; order = []
for p in pages:
    if p in SKIP_PAGES: continue
    blocks = open(os.path.join(d, p+'.sh')).read().rstrip('\n').split('\n#----\n')
    body = []
    for b in blocks:
        for pg, old, new in REPLACE:
            if pg == p and old in b: assert b.count(old) == 1, (p, old); b = b.replace(old, new); used.add((pg, old))
        if any(b.startswith(s) for s in SKIP.get(p, [])):
            body.append('# [skipped] ' + b.split('\n')[0]); used.add((p, 'skip:'+b.split('\n')[0][:20])); continue
        if any(b.startswith(s) for s in DIAG):
            body.append('{\n' + b + '\n} || true  # diagnostic, prints matches only'); continue
        if TEST_RE.search(b) and p not in FATAL_TESTS:
            body.append('{\n' + b + '\n} || testfail "' + p + '"'); continue
        body.append(b)
    if p in EXTRA_AFTER: body.append(EXTRA_AFTER[p])
    fn = 'pkg_' + p.lower().replace('-', '_')
    if p == 'glibc':
        body.insert(0, '# Autark flags without FORTIFY/LDFLAGS: glibc refuses forced _FORTIFY_SOURCE and links ld.so itself.\n# Fortification comes from --enable-fortify-source=3 below. Runs in build()\'s subshell, so this is local.\nexport CFLAGS="-O2 -march=x86-64-v3 -pipe -fstack-clash-protection -fcf-protection=full" CXXFLAGS="-O2 -march=x86-64-v3 -pipe -fstack-clash-protection -fcf-protection=full"\nunset LDFLAGS')
    fns.append(f'{fn}() {{\n' + '\n'.join(body) + '\n}\n')
    order.append((p, fn, None if p in NOSRC else tarball(p)))
missing = [r for r in REPLACE if (r[0], r[1]) not in used]
assert not missing, missing
skipcount = sum(len(v) for v in SKIP.values())
head = open(os.path.join(d, 'head.sh')).read()
cases = '\n'.join(f'    {p.lower().replace("-","_")}) run_pkg {p} {t or "-"} {fn} ;;' for p, fn, t in order)
names = ' '.join(p.lower().replace('-','_') for p, _, _ in order)
tail = f'''
packages=("${{@:-{names}}}")
for p in ${{packages[@]}}; do
  case $p in
{cases}
    *) echo "unknown package: $p" >&2; exit 2 ;;
  esac
done
echo "== chapter 8 done"
'''
open(out, 'w').write(head + '\n' + '\n'.join(fns) + tail)
print(f"{len(order)} packages, {skipcount} skip rules, {len(REPLACE)} replacements applied")
