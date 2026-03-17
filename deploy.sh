#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <device-env-file>" >&2
    echo "Example: $0 devices/sw2.env" >&2
    exit 1
fi

if [[ ! -f "$1" ]]; then
    echo "Error: $1 not found" >&2
    exit 1
fi

# Load device variables (exported for envsubst)
set -a
# shellcheck source=/dev/null
source "$1"
set +a

SSH_USER="${SSH_USER:-admin}"
SSH="ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"
SCP="scp -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -q"
HOST="${SSH_USER}@${ROUTER_ID}"

RENDERED=$(mktemp)
trap 'rm -f "$RENDERED"' EXIT

echo "=== Deploying ${DEVICE_NAME} (${ROUTER_ID}) ==="

# --- Phase 1: Base L2/L3 config ---
echo "--- Phase 1: base.rsc ---"
envsubst '${DEVICE_NAME} ${MGMT_IP}' < "$SCRIPT_DIR/templates/base.rsc" > "$RENDERED"
$SCP "$RENDERED" "${HOST}:base.rsc"
# Import runs on-switch — survives SSH drops during L2MTU switch chip reset
$SSH "$HOST" '/import file-name=base.rsc' || true
sleep 3

# --- Phase 1.5: Discover link-local address ---
echo "--- Discovering link-local address ---"
for attempt in 1 2 3; do
    RAW=$($SSH "$HOST" ':put [/ipv6 address get [find interface=vlan101 link-local] address]' 2>/dev/null) && break
    echo "  attempt ${attempt}/3..."
    sleep 3
done

export LINK_LOCAL
LINK_LOCAL=$(echo "$RAW" | tr -d '\r' | sed 's|/.*||')

if [[ -z "$LINK_LOCAL" ]]; then
    echo "Error: could not discover link-local on vlan101" >&2
    exit 1
fi
echo "  LINK_LOCAL=${LINK_LOCAL}"

# --- Phase 2: BGP config ---
echo "--- Phase 2: bgp.rsc ---"
envsubst '${AS} ${ROUTER_ID} ${LINK_LOCAL}' < "$SCRIPT_DIR/templates/bgp.rsc" > "$RENDERED"
$SCP "$RENDERED" "${HOST}:bgp.rsc"
$SSH "$HOST" '/import file-name=bgp.rsc'

# Clean up remote files
$SSH "$HOST" '/file remove base.rsc,bgp.rsc' 2>/dev/null || true

echo ""
echo "=== Done ==="
echo "Verify: ssh ${HOST} '/routing bgp connection print'"
