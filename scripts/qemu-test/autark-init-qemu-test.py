#!/usr/bin/env python3
"""qemu test of autark-init (roadmap M4, docs/specs/autark-init.md).

Run as root on a machine with qemu-system-x86_64, swtpm, cryptsetup and mkfs.ext4 (the Ubuntu partition has them):

    sudo python3 autark-init-qemu-test.py autark-init-test-bundle.tar

The bundle is made on Autark by autark-init-bundle.sh. This builds a LUKS2 disk holding a small root with a test init, starts a software
TPM, and boots Autark's kernel with the Rust initramfs in qemu, typing at the console like a person: right and wrong passphrases, no
disk, a bad root=, the TPM before and after a TPM2 + PIN is enrolled (from inside the guest), wrong PINs, and the recovery key. Each
case passes only if the console shows what it should, including the test init reporting that it is PID 1 on the unlocked root with
/proc, /sys, /dev and /run moved over and the initramfs gone. It changes nothing outside its work folder. Python 3 standard library only.

    --keep          keep the work folder (disk, logs) afterwards
    --only NAME...  run only these cases (the enrolment case comes first if a TPM case needs it)
    --slow          wait 4 times as long for each step (qemu without KVM is slow)
"""
import argparse
import os
import re
import select
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import time

# No spaces: the enrolment case passes it to the guest on the kernel command line.
PASSPHRASE = "correct-horse-battery"
PIN = "2468"
PASS_PROMPT = "Passphrase or recovery key: "
PIN_PROMPT = "TPM PIN: "
MARK = "AUTARK-INIT-TEST PASS"
ROOT_PASSPHRASE_BYTES = PASSPHRASE.encode()


class Fail(Exception):
    pass


def need(tool):
    if shutil.which(tool) is None:
        sys.exit(f"autark-init-qemu-test: needs {tool} (on Ubuntu: sudo apt install qemu-system-x86 swtpm cryptsetup e2fsprogs)")


def run(*cmd, **kw):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kw)


class Rig:
    """The work folder, the test disk, and the software TPM."""

    def __init__(self, bundle, keep, slow):
        self.keep = keep
        self.scale = 4 if slow else 1
        self.work = tempfile.mkdtemp(prefix="autark-init-qemu-")
        self.dir = os.path.join(self.work, "bundle")
        os.makedirs(self.dir)
        with tarfile.open(bundle) as tar:
            tar.extractall(self.dir)
        self.kernel = os.path.join(self.dir, "vmlinuz")
        self.initrd = os.path.join(self.dir, "initramfs-rust.img")
        self.disk = os.path.join(self.work, "disk.img")
        self.uuid = ""
        self.recovery_key = None
        self.swtpm = None
        self.current = None  # the Vm of the case that is running, so a failing case can still be stopped and shown
        self.tpm_dir = os.path.join(self.work, "tpm")
        self.tpm_sock = os.path.join(self.work, "swtpm.sock")
        for path in (self.kernel, self.initrd, os.path.join(self.dir, "rootfs")):
            if not os.path.exists(path):
                sys.exit(f"autark-init-qemu-test: the bundle has no {os.path.basename(path)}")

    def make_disk(self):
        """A 192 MB LUKS2 volume (cheap key derivation: this is a test) holding the bundle's rootfs as ext4."""
        run("truncate", "-s", "192M", self.disk)
        key = os.path.join(self.work, "key")
        with open(key, "wb") as f:
            f.write(ROOT_PASSPHRASE_BYTES)
        run("cryptsetup", "luksFormat", "--type", "luks2", "--pbkdf", "pbkdf2", "--pbkdf-force-iterations", "1000", "--batch-mode", "--key-file", key, self.disk)
        self.uuid = run("cryptsetup", "luksUUID", self.disk).stdout.strip()
        name = f"autarktest{os.getpid()}"
        mount = os.path.join(self.work, "mnt")
        os.makedirs(mount)
        run("cryptsetup", "open", "--key-file", key, self.disk, name)
        try:
            run("mkfs.ext4", "-q", "-F", f"/dev/mapper/{name}")
            run("mount", f"/dev/mapper/{name}", mount)
            try:
                run("cp", "-a", os.path.join(self.dir, "rootfs") + "/.", mount)
                run("chown", "-R", "0:0", mount)
            finally:
                run("umount", mount)
        finally:
            run("cryptsetup", "close", name)
        os.remove(key)

    def start_tpm(self):
        """swtpm serves one qemu run and exits when qemu disconnects, so every run that wants a TPM starts its own. The state folder stays,
        so what one run did to the TPM (the enrolled key) is there for the next."""
        if self.swtpm and self.swtpm.poll() is None:
            self.swtpm.terminate()
            self.swtpm.wait(5)
        os.makedirs(self.tpm_dir, exist_ok=True)
        if os.path.exists(self.tpm_sock):
            os.remove(self.tpm_sock)
        self.swtpm = subprocess.Popen(
            ["swtpm", "socket", "--tpm2", "--tpmstate", f"dir={self.tpm_dir}", "--ctrl", f"type=unixio,path={self.tpm_sock}", "--flags", "not-need-init,startup-clear", "--log", f"file={self.work}/swtpm.log"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(50):
            if os.path.exists(self.tpm_sock):
                return
            time.sleep(0.1)
        sys.exit("autark-init-qemu-test: swtpm didn't start (see swtpm.log in the work folder)")

    def stop(self):
        if self.swtpm:
            self.swtpm.terminate()
            try:
                self.swtpm.wait(5)
            except subprocess.TimeoutExpired:
                self.swtpm.kill()
        if self.keep:
            print(f"work folder kept: {self.work}")
        else:
            shutil.rmtree(self.work, ignore_errors=True)


class Vm:
    """One qemu run, driven through its serial console."""

    def __init__(self, rig, name, disk=True, tpm=False, snapshot=True, luks_options="", root=None, extra=""):
        self.rig, self.name = rig, name
        cmdline = f"console=ttyS0,115200 loglevel=4 rd.timeout=6 init=/test-payload rw {extra}"
        if disk:
            cmdline += f" rd.luks.name={rig.uuid}=autark"
            if luks_options:
                cmdline += f" rd.luks.options={rig.uuid}={luks_options}"
        cmdline += f" root={root or '/dev/mapper/autark'}"
        args = [os.environ.get("AUTARK_QEMU", "qemu-system-x86_64"), "-machine", "q35", "-m", "1024", "-smp", "2", "-display", "none", "-serial", "stdio", "-monitor", "none", "-no-reboot",
                "-kernel", rig.kernel, "-initrd", rig.initrd, "-append", cmdline]
        args += ["-enable-kvm", "-cpu", "host"] if os.access("/dev/kvm", os.W_OK) else ["-cpu", "max"]
        if disk:
            args += ["-drive", f"file={rig.disk},if=none,id=d0,format=raw" + (",snapshot=on" if snapshot else ""), "-device", "nvme,drive=d0,serial=autarktest"]
        if tpm:
            rig.start_tpm()
            args += ["-chardev", f"socket,id=chrtpm,path={rig.tpm_sock}", "-tpmdev", "emulator,id=tpm0,chardev=chrtpm", "-device", "tpm-tis,tpmdev=tpm0"]
        self.cmdline = cmdline
        rig.current = self
        self.log_path = os.path.join(rig.work, f"{name}.log")
        self.log = open(self.log_path, "w")
        self.log.write(f"# {' '.join(args)}\n")
        self.proc = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        os.set_blocking(self.proc.stdout.fileno(), False)
        self.buffer, self.at = "", 0

    def _read(self, wait):
        ready, _, _ = select.select([self.proc.stdout], [], [], wait)
        if ready:
            data = os.read(self.proc.stdout.fileno(), 65536)
            if data:
                text = data.decode(errors="replace")
                self.buffer += text
                self.log.write(text)
                self.log.flush()
                return True
        return False

    def expect(self, text, timeout=60):
        """Waits for `text` to appear after what was last matched."""
        deadline = time.time() + timeout * self.rig.scale
        while True:
            found = self.buffer.find(text, self.at)
            if found >= 0:
                self.at = found + len(text)
                return
            if self.proc.poll() is not None and not self._read(0.2):
                raise Fail(f"qemu stopped before {text!r} appeared")
            if time.time() > deadline:
                raise Fail(f"{text!r} never appeared in {timeout * self.rig.scale} s")
            self._read(0.2)

    def capture(self, pattern, timeout=60):
        """Like expect, for a regex; returns its first group. The console arrives in pieces, so a pattern that ends in `\\S+` would match
        the first piece of a word: end it with a lookahead for the whitespace after it, `(?=\\s)`."""
        deadline = time.time() + timeout * self.rig.scale
        while True:
            match = re.compile(pattern).search(self.buffer, self.at)
            if match:
                self.at = match.end()
                return match.group(1)
            if time.time() > deadline or (self.proc.poll() is not None and not self._read(0.2)):
                raise Fail(f"{pattern!r} never appeared")
            self._read(0.2)

    def send(self, line=""):
        time.sleep(0.4)  # after the prompt, so the console has switched echo off
        self.proc.stdin.write((line + "\n").encode())
        self.proc.stdin.flush()

    def finish(self, timeout=60):
        """The guest powers off or restarts; with -no-reboot, either ends qemu."""
        deadline = time.time() + timeout * self.rig.scale
        while self.proc.poll() is None:
            self._read(0.2)
            if time.time() > deadline:
                raise Fail("the guest didn't power off")
        while self._read(0.1):
            pass

    def close(self):
        if self.proc.poll() is None:
            self.proc.kill()
        self.proc.wait()
        self.log.close()

    def tail(self, lines=25):
        return "\n".join(self.buffer.splitlines()[-lines:])


# ---- the cases. Each boots a guest and types at it; any Fail ends the case.

def passes(vm):
    vm.expect(MARK)
    vm.finish()


def case_passphrase(rig):
    vm = Vm(rig, "passphrase")
    vm.expect(PASS_PROMPT, 120)
    vm.send(PASSPHRASE)
    vm.expect("autark unlocked.")
    passes(vm)
    return vm


def case_passphrase_retry(rig):
    vm = Vm(rig, "passphrase-retry")
    vm.expect(PASS_PROMPT, 120)
    vm.send("not the passphrase")
    vm.expect("That isn't right.")
    vm.expect(PASS_PROMPT)
    vm.send(PASSPHRASE)
    vm.expect("autark unlocked.")
    passes(vm)
    return vm


def case_three_wrong(rig):
    vm = Vm(rig, "three-wrong")
    vm.expect(PASS_PROMPT, 120)
    for _ in range(3):
        vm.send("nope")
        vm.expect("That isn't right.")
        if _ < 2:
            vm.expect(PASS_PROMPT)
    vm.expect("three wrong tries")
    vm.expect("Press Enter to restart")
    vm.send()
    vm.finish()
    return vm


def case_no_disk(rig):
    vm = Vm(rig, "no-disk", disk=False, extra=f"rd.luks.name={rig.uuid}=autark")
    vm.expect("didn't appear within 6 seconds", 120)
    vm.expect("Press Enter to restart")
    vm.send()
    vm.finish()
    return vm


def case_bad_root(rig):
    vm = Vm(rig, "bad-root", root="/dev/mapper/nope")
    vm.expect(PASS_PROMPT, 120)
    vm.send(PASSPHRASE)
    vm.expect("autark unlocked.")
    vm.expect("autark-init:")
    vm.expect("/dev/mapper/nope")
    vm.expect("Press Enter to restart")
    vm.send()
    vm.finish()
    return vm


def case_tpm_without_token(rig):
    vm = Vm(rig, "tpm-without-token", tpm=True, luks_options="tpm2-device=auto")
    vm.expect("Use the passphrase or the recovery key instead.", 120)
    vm.expect(PASS_PROMPT)
    vm.send(PASSPHRASE)
    vm.expect("autark unlocked.")
    passes(vm)
    return vm


def case_enroll(rig):
    # No snapshot: this is the one case that writes the disk (the TPM2 token and the recovery key go in the LUKS header).
    vm = Vm(rig, "enroll", tpm=True, snapshot=False, extra=f"autark.test=enroll autark.test.device=/dev/nvme0n1 autark.test.passphrase={PASSPHRASE} autark.test.pin={PIN}")
    vm.expect(PASS_PROMPT, 120)
    vm.send(PASSPHRASE)
    vm.expect("autark unlocked.")
    vm.expect("TEST ok: enrolled the TPM2 + PIN", 120)
    rig.recovery_key = vm.capture(r"TEST recovery-key: (\S+)(?=\s)")  # the (?=\s): not before the line is complete
    passes(vm)
    return vm


def case_tpm_pin(rig):
    vm = Vm(rig, "tpm-pin", tpm=True, luks_options="tpm2-device=auto")
    vm.expect(PIN_PROMPT, 120)
    vm.send(PIN)
    vm.expect("autark unlocked with the TPM.")
    vm.expect("TEST ok: the TPM is visible to the real init")
    passes(vm)
    return vm


def three_wrong_pins(vm):
    vm.expect(PIN_PROMPT, 120)
    for n in range(3):
        vm.send("0000")
        vm.expect("That PIN isn't right.")
        if n < 2:
            vm.expect(PIN_PROMPT)
    vm.expect("Use the passphrase or the recovery key instead.")
    vm.expect(PASS_PROMPT)


def case_tpm_wrong_pin(rig):
    vm = Vm(rig, "tpm-wrong-pin", tpm=True, luks_options="tpm2-device=auto")
    three_wrong_pins(vm)
    vm.send(PASSPHRASE)
    vm.expect("autark unlocked.")
    passes(vm)
    return vm


def diagnose_recovery_key(rig):
    """Asks the host's cryptsetup whether the test disk accepts the recovery key (and the passphrase, as a control), and prints what the
    disk has in its header. If the host accepts the key but the guest refuses it, the fault is in autark-init, not in the enrolment."""
    print(f"  recovery key from the enrol case: {rig.recovery_key!r} ({len(rig.recovery_key)} characters)")
    for what, secret in (("passphrase", PASSPHRASE), ("recovery key", rig.recovery_key)):
        done = subprocess.run(["cryptsetup", "open", "--test-passphrase", "--key-file=-", rig.disk], input=secret.encode(), capture_output=True)
        print(f"  host cryptsetup on the {what}: {'accepted' if done.returncode == 0 else 'REFUSED (' + done.stderr.decode().strip() + ')'}")
    dump = subprocess.run(["cryptsetup", "luksDump", rig.disk], capture_output=True, text=True).stdout
    keep = [line for line in dump.splitlines() if line.startswith(("Keyslots:", "Tokens:", "Digests:")) or line[:3].strip().rstrip(":").isdigit() or "Priority" in line or "PBKDF" in line]
    print("  header:\n    " + "\n    ".join(keep))


def case_recovery_key(rig):
    if not rig.recovery_key:
        raise Fail("no recovery key (the enrol case didn't run or failed)")
    diagnose_recovery_key(rig)
    vm = Vm(rig, "recovery-key", tpm=True, luks_options="tpm2-device=auto")
    three_wrong_pins(vm)
    vm.send(rig.recovery_key)
    vm.expect("autark unlocked.")
    passes(vm)
    return vm


CASES = [
    ("passphrase", case_passphrase, False),
    ("passphrase-retry", case_passphrase_retry, False),
    ("three-wrong", case_three_wrong, False),
    ("no-disk", case_no_disk, False),
    ("bad-root", case_bad_root, False),
    ("tpm-without-token", case_tpm_without_token, False),
    ("enroll", case_enroll, False),
    ("tpm-pin", case_tpm_pin, True),
    ("tpm-wrong-pin", case_tpm_wrong_pin, True),
    ("recovery-key", case_recovery_key, True),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("bundle")
    parser.add_argument("--keep", action="store_true")
    parser.add_argument("--only", nargs="+", metavar="NAME")
    parser.add_argument("--slow", action="store_true")
    args = parser.parse_args()
    if os.geteuid() != 0:
        sys.exit("autark-init-qemu-test: run it as root (sudo): it makes a LUKS volume with cryptsetup and mounts it")
    for tool in ("qemu-system-x86_64", "swtpm", "cryptsetup", "mkfs.ext4", "truncate", "mount", "umount"):
        need(tool)
    wanted = [name for name, _, _ in CASES]
    if args.only:
        unknown = [name for name in args.only if name not in wanted]
        if unknown:
            sys.exit(f"unknown cases {unknown}; they are: {', '.join(wanted)}")
        selected = set(args.only)
        if any(needs_token for name, _, needs_token in CASES if name in selected):
            selected.add("enroll")
        if "recovery-key" in selected:
            selected.add("enroll")
    else:
        selected = set(wanted)

    rig = Rig(args.bundle, args.keep, args.slow)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(130))
    results = []
    try:
        print("making the test disk…")
        rig.make_disk()
        print(f"disk UUID {rig.uuid}; kernel and initramfs from the bundle:\n{open(os.path.join(rig.dir, 'MANIFEST')).read()}")
        for name, case, _ in CASES:
            if name not in selected:
                continue
            started = time.time()
            rig.current = None
            try:
                case(rig)
                results.append((name, True, f"{time.time() - started:.0f} s", ""))
            except Fail as why:
                results.append((name, False, f"{time.time() - started:.0f} s", str(why)))
                print(f"\n--- {name} failed: {why}\n{rig.current.tail() if rig.current else ''}\n---")
            finally:
                if rig.current:
                    rig.current.close()
            print(f"{'PASS' if results[-1][1] else 'FAIL'}  {name}  ({results[-1][2]})")
    finally:
        rig.stop()
    print("\nresults:")
    for name, ok, took, why in results:
        print(f"  {'PASS' if ok else 'FAIL'}  {name:20} {took:>6}  {why}")
    failed = [name for name, ok, _, _ in results if not ok]
    print(f"\n{len(results) - len(failed)} of {len(results)} passed" + (f"; failed: {', '.join(failed)}" if failed else ""))
    if failed:
        print(f"Console logs are in the work folder ({rig.work}); run again with --keep to keep them.")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
