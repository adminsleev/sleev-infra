#!/usr/bin/env bash
set -euo pipefail

KEYFILE="$HOME/.config/sops/age/keys.txt"

if [[ -f "$KEYFILE" ]]; then
    echo "ERROR: age key already exists at $KEYFILE"
    echo "Delete it manually if you intend to rotate keys."
    exit 1
fi

mkdir -p "$(dirname "$KEYFILE")"
age-keygen -o "$KEYFILE"

echo ""
echo "==> Age keypair generated at $KEYFILE"
echo ""
echo "Your PUBLIC key (add this to secrets/.sops.yaml):"
grep "^# public key:" "$KEYFILE" | awk '{print $NF}'
echo ""
echo "WARNING: NEVER commit $KEYFILE to git."
echo "         Back it up securely offline."
