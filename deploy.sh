#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <device-env-file> [current-ip]" >&2
    echo "Examples:" >&2
    echo "  $0 devices/sw1.env                # re-deploy (connects to ROUTER_ID)" >&2
    echo "  $0 devices/sw1.env 192.168.88.1   # after manual reset" >&2
    echo "  $0 devices/orangepi5-plus.env      # deploy FRR peer" >&2
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

RENDERED=$(mktemp -d)
trap 'rm -rf "$RENDERED"' EXIT

SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"

# --- Switch deployment (has ROUTER_ID) ---
if [[ -n "${ROUTER_ID:-}" ]]; then
    SSH_USER="${SSH_USER:-admin}"
    CURRENT_IP="${2:-${ROUTER_ID}}"
    HOST="${SSH_USER}@${CURRENT_IP}"
    SSH="ssh $SSH_OPTS"
    SCP="scp $SSH_OPTS -q"

    echo "=== Deploying switch ${DEVICE_NAME} (${CURRENT_IP} -> ${ROUTER_ID}) ==="

    # Render all templates
    echo "--- Rendering templates ---"
    envsubst '${DEVICE_NAME} ${MGMT_IP}' \
        < "$SCRIPT_DIR/templates/base.rsc" > "$RENDERED/base.rsc"
    envsubst '${AS} ${ROUTER_ID} ${MGMT_IP}' \
        < "$SCRIPT_DIR/templates/bgp.rsc" > "$RENDERED/bgp.rsc"
    envsubst '${UPSTREAM_GW}' \
        < "$SCRIPT_DIR/templates/upstream.rsc" > "$RENDERED/upstream.rsc"

    # Create setup script that runs after reset
    cat > "$RENDERED/setup.rsc" <<'SETUP'
# Import SSH key (must happen before anything that might drop connectivity)
/user ssh-keys import public-key-file=sshkey.pub user=admin
# Import configuration phases
/import file-name=base.rsc
/import file-name=bgp.rsc
/import file-name=upstream.rsc
# Clean up
/file remove sshkey.pub,setup.rsc,base.rsc,bgp.rsc,upstream.rsc
SETUP

    # Upload everything
    echo "--- Uploading files ---"
    $SCP ~/.ssh/id_rsa.pub "${HOST}:sshkey.pub"
    $SCP "$RENDERED/base.rsc" "$RENDERED/bgp.rsc" "$RENDERED/upstream.rsc" \
        "$RENDERED/setup.rsc" "${HOST}:"

    # Reset and apply
    echo "--- Resetting switch (will reboot) ---"
    $SSH "$HOST" '/system reset-configuration run-after-reset=setup.rsc' || true

    # Wait for switch to come back at its configured IP
    echo "--- Waiting for ${DEVICE_NAME} at ${ROUTER_ID} ---"
    TARGET="${SSH_USER}@${ROUTER_ID}"
    for i in $(seq 1 30); do
        if ssh $SSH_OPTS -o ConnectTimeout=3 "$TARGET" '/system identity print' &>/dev/null; then
            echo ""
            echo "=== Done ==="
            echo "Verify: ssh ${TARGET} '/routing bgp connection print'"
            exit 0
        fi
        printf "."
        sleep 2
    done
    echo ""
    echo "Warning: switch did not come back within 60s at ${ROUTER_ID}" >&2
    exit 1

# --- Peer deployment (has PEER_INTERFACE) ---
elif [[ -n "${PEER_INTERFACE:-}" ]]; then
    SSH_USER="${SSH_USER:-$(whoami)}"
    HOST="${SSH_USER}@${DEPLOY_IP}"
    SSH="ssh $SSH_OPTS"
    SCP="scp $SSH_OPTS -q"

    echo "=== Deploying peer ${DEVICE_NAME} (${DEPLOY_IP}) ==="

    # FRR config
    echo "--- frr.conf ---"
    envsubst '${DEVICE_NAME} ${AS} ${PEER_INTERFACE} ${PEER_REMOTE_AS} ${ANNOUNCED_PREFIX}' \
        < "$SCRIPT_DIR/templates/frr.conf" > "$RENDERED/frr.conf"
    $SCP "$RENDERED/frr.conf" "${HOST}:frr.conf"
    $SSH "$HOST" 'sudo cp frr.conf /etc/frr/frr.conf && rm frr.conf'

    # systemd-networkd: dummy interface
    echo "--- dummy.netdev + dummy.network ---"
    $SCP "$SCRIPT_DIR/templates/dummy.netdev" "${HOST}:dummy.netdev"
    $SSH "$HOST" 'sudo cp dummy.netdev /etc/systemd/network/10-dummy.netdev && rm dummy.netdev'

    envsubst '${ANNOUNCED_IP}' < "$SCRIPT_DIR/templates/dummy.network" > "$RENDERED/dummy.network"
    $SCP "$RENDERED/dummy.network" "${HOST}:dummy.network"
    $SSH "$HOST" 'sudo cp dummy.network /etc/systemd/network/10-dummy.network && rm dummy.network'

    # systemd-networkd: peering interface
    echo "--- peering.network ---"
    envsubst '${PEER_INTERFACE} ${GATEWAY_LL}' \
        < "$SCRIPT_DIR/templates/peering.network" > "$RENDERED/peering.network"
    $SCP "$RENDERED/peering.network" "${HOST}:peering.network"
    $SSH "$HOST" 'sudo cp peering.network /etc/systemd/network/05-peering.network && rm peering.network'

    # Restart services
    echo "--- Restarting services ---"
    $SSH "$HOST" 'sudo systemctl restart systemd-networkd && sudo systemctl restart frr'

    echo ""
    echo "=== Done ==="
    echo "Verify: ssh ${HOST} 'sudo vtysh -c \"show bgp summary\"'"

else
    echo "Error: env file must define ROUTER_ID (switch) or PEER_INTERFACE (peer)" >&2
    exit 1
fi
