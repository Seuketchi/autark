# generic

A profile for hardware Autark has never seen. `kernel.config` is the Ubuntu x86-64 config this project captured from
its first laptop (Linux 7.0.14, `/boot/config-*`), with every driver as a module.
There is no `lsmod.txt`, so the kernel build keeps all of those modules instead of trimming them, and there is no
`kernel.fragment`: the required options in `scripts/lfs/ch10-kernel-inside.sh` are all it adds.

Use it with `LFS=/mnt/lfs scripts/lfs/stage-profile.sh generic`. The kernel is larger and takes longer to build than a
trimmed one. To trim it for a machine, capture that machine with `scripts/capture-hardware.sh <name>`.
