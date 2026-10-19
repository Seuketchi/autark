#!/bin/sh
# Prints which TPM PCRs the LUKS TPM2 keyslot is bound to (and whether a PIN is set). Reads the LUKS header only;
# prints no key, blob or secret. Run as root:  su -c 'sh /home/tan/pcr-check.sh'
DEV=/dev/disk/by-uuid/33727520-d460-4861-b27f-bef08d44c11f
cryptsetup luksDump --dump-json-metadata "$DEV" | python3 -c '
import sys, json
d = json.load(sys.stdin)
for k, v in d["tokens"].items():
    if v.get("type") == "systemd-tpm2":
        print("token", k, {x: v.get(x) for x in ("tpm2-pcrs", "tpm2-pubkey-pcrs", "tpm2-pin", "tpm2-pcr-bank")})
' > /home/tan/pcr-check.txt
chown tan /home/tan/pcr-check.txt
echo written
