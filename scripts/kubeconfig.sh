#!/usr/bin/env bash
# Write the k3s admin kubeconfig to ~/.kube/hgd1.yaml (mode 600), pointing at
# the API VIP name. It is a cluster-admin credential: never commit or print it.
# Usage: scripts/kubeconfig.sh [server-vm]   (default: first enabled server)
# Env: KUBECONFIG_OUT=<path> to write elsewhere.
set -euo pipefail
command -v jq >/dev/null || exec nix shell nixpkgs#jq -c "$0" "$@"
cd "$(git rev-parse --show-toplevel)"
INVENTORY=$(nix eval --json --file inventory.nix)
VM="${1:-$(jq -r '[.vms | to_entries[] | select(.value.enabled and .value.role == "server")][0].key' <<<"$INVENTORY")}"
jq -e --arg vm "$VM" '.vms[$vm].role == "server" and .vms[$vm].enabled' <<<"$INVENTORY" >/dev/null \
  || { echo "$VM is not an enabled server VM" >&2; exit 1; }
EXPECTED=$(jq -r --arg vm "$VM" '.vms[$vm].hostKey // empty' <<<"$INVENTORY")
[ -n "$EXPECTED" ] || { echo "$VM: pin its hostKey in inventory first (docs/compute/vms.md)" >&2; exit 1; }
ADDR=$(jq -r --arg vm "$VM" '.vms[$vm].ip.k8s' <<<"$INVENTORY")
API="https://$(jq -r '.k3s.apiName' <<<"$INVENTORY"):6443"
OUT="${KUBECONFIG_OUT:-$HOME/.kube/hgd1.yaml}"
DEST="${SSH_USER:-jurre}@$ADDR"
OPTS=(-o BatchMode=yes -o ConnectTimeout=10)

ACTUAL=$(ssh "${OPTS[@]}" "$DEST" 'cat /var/lib/ssh/ssh_host_ed25519_key.pub' | awk '{print $1" "$2}')
[ "$ACTUAL" = "$EXPECTED" ] || { echo "$VM: SSH host key differs from inventory" >&2; exit 1; }

umask 077
mkdir -p "$(dirname "$OUT")"
TMP=$(mktemp "$OUT.XXXXXX")
trap 'rm -f "$TMP"' EXIT
ssh "${OPTS[@]}" "$DEST" 'sudo -n cat /etc/rancher/k3s/k3s.yaml' \
  | sed -e "s#https://127.0.0.1:6443#$API#" \
        -e 's/^\( *\(- \)\{0,1\}\(name\|cluster\|user\|current-context\)\): default$/\1: hgd1/' >"$TMP"
grep -q "server: $API" "$TMP" || { echo "unexpected kubeconfig from $VM" >&2; exit 1; }
mv "$TMP" "$OUT"
trap - EXIT
echo "wrote $OUT (context hgd1, server $API)"
