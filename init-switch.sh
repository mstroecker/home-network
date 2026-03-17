#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <switch-ip>" >&2
    echo "Example: $0 192.168.90.1" >&2
    exit 1
fi

HOST="admin@$1"

scp ~/.ssh/id_rsa.pub "${HOST}:sshkey.pub"
ssh "$HOST" '/user ssh-keys import public-key-file=sshkey.pub user=admin'
echo "SSH key imported on $1."
