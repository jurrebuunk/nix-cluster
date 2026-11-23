#!/usr/bin/env bash
# Restart k3s VMs one at a time, e.g. to boot a newly deployed runner:
# all nodes Ready -> drain -> restart -> new boot Ready -> uncordon.
# Usage: scripts/k3s-roll.sh [vm...]   (default: all enabled VMs, agents first)
# Needs KUBECONFIG (scripts/kubeconfig.sh) and WARP or a site network.
set -euo pipefail
command -v jq >/dev/null || exec nix shell nixpkgs#jq -c "$0" "$@"
command -v kubectl >/dev/null || exec nix shell nixpkgs#kubectl -c "$0" "$@"
cd "$(git rev-parse --show-toplevel)"
INVENTORY=$(nix eval --json --file inventory.nix)
EXPECTED=$(jq '[.vms[] | select(.enabled)] | length' <<<"$INVENTORY")
if [ $# -gt 0 ]; then
  VMS=("$@")
else
  mapfile -t VMS < <(jq -r '.vms | to_entries | map(select(.value.enabled)) | sort_by(.value.role != "agent") | .[].key' <<<"$INVENTORY")
fi

# Every enabled VM is a node and Ready: restarting one never costs quorum.
all_ready() {
  kubectl get nodes -o json | jq -e --argjson n "$EXPECTED" '
    (.items | length) == $n and
    all(.items[]; any(.status.conditions[]; .type == "Ready" and .status == "True"))' >/dev/null
}
boot_id() { kubectl get node "$1" -o jsonpath='{.status.nodeInfo.bootID}'; }
node_ready() {
  kubectl get node "$1" -o json | jq -e 'any(.status.conditions[]; .type == "Ready" and .status == "True")' >/dev/null
}

for VM in "${VMS[@]}"; do
  jq -e --arg vm "$VM" '.vms[$vm].enabled' <<<"$INVENTORY" >/dev/null || { echo "$VM: not an enabled VM" >&2; exit 1; }
  all_ready || { echo "not all $EXPECTED nodes are Ready; refusing to restart $VM" >&2; kubectl get nodes >&2; exit 1; }
  BEFORE=$(boot_id "$VM")
  echo "==> $VM: drain"
  kubectl drain "$VM" --ignore-daemonsets --delete-emptydir-data --timeout=300s
  echo "==> $VM: restart"
  scripts/vm.sh "$VM" restart
  echo "==> $VM: waiting for a new boot to be Ready"
  for _ in $(seq 1 120); do
    if [ "$(boot_id "$VM" 2>/dev/null)" != "$BEFORE" ] && node_ready "$VM"; then break; fi
    sleep 5
  done
  if [ "$(boot_id "$VM")" = "$BEFORE" ] || ! node_ready "$VM"; then
    echo "$VM did not come back Ready within 10 minutes; left cordoned" >&2
    exit 1
  fi
  kubectl uncordon "$VM"
  kubectl get --raw='/readyz' >/dev/null
done
kubectl get nodes -L topology.kubernetes.io/zone
