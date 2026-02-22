#!/bin/bash
set -e

KEY_DIR="$(dirname "$0")/../greenplum/ssh"
mkdir -p "$KEY_DIR"

if [[ -f "$KEY_DIR/id_rsa" ]]; then
    echo "[INFO] SSH keys already exist in $KEY_DIR — skipping generation."
    exit 0
fi

ssh-keygen -t rsa -b 4096 -f "$KEY_DIR/id_rsa" -N "" -C "greenplum-cluster"
cp "$KEY_DIR/id_rsa.pub" "$KEY_DIR/authorized_keys"

chmod 700 "$KEY_DIR"
chmod 600 "$KEY_DIR/id_rsa"
chmod 644 "$KEY_DIR/id_rsa.pub"
chmod 644 "$KEY_DIR/authorized_keys"

echo "[OK] SSH key pair created"
