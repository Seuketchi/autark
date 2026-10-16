# ch8-inside.sh generator

`ch8-inside.sh` is generated, not hand-written: `gen.py` takes the book's chapter 8 pages, keeps each command
block verbatim, and applies the curation in its `SKIP`, `REPLACE`, `FATAL_TESTS` and `DIAG` tables (each rule
must match, or generation fails). `head.sh` is the hand-written header: chroot guard, Autark's flags,
package tracking and test logging. `brief.py` prints every block with the sentence before it, which is how
each page was curated.

Regenerate after changing a rule:

    for p in $(cat pages.txt); do curl -fsSLO https://www.linuxfromscratch.org/lfs/view/stable-systemd/chapter08/$p; done
    # extract each page's blocks to <page>.sh (one block per "#----" separator), then:
    python3 gen.py <dir with pages and head.sh> $LFS/sources/wget-list-systemd ../ch8-inside.sh
