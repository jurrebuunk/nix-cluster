#!/usr/bin/env bash
# Operate a declaratively enabled VM; never create/move/delete its disks here.
# Usage: vm.sh list | vm.sh <name> [status|start|stop|restart|logs]
# JUMP=root@192.168.2.12 during bootstrap. Stop/restart do NOT drain k3s.
# Validated actions and shell-quoted unit names intentionally expand locally.
# shellcheck disable=SC2029
set -euo pipefail
command -v jq >/dev/null || exec nix shell nixpkgs#jq -c "$0" "$@"
cd "$(git rev-parse --show-toplevel)"
INVENTORY=$(nix eval --json --file inventory.nix)
if [ "${1:-list}" = list ]; then
  jq -r '.vms | to_entries[] | [.key, .value.host, (if .value.enabled then "enabled" else "disabled" end), .value.ip.k8s, .value.ip.storage] | @tsv' <<<"$INVENTORY"
  exit 0
fi
VM="$1"; ACTION="${2:-status}"
case "$ACTION" in status|start|stop|restart|logs) ;; *) echo "Unknown action: $ACTION" >&2; exit 1;; esac
jq -e --arg vm "$VM" '.vms | has($vm)' <<<"$INVENTORY" >/dev/null || { echo "Unknown VM: $VM" >&2; exit 1; }
jq -e --arg vm "$VM" '.vms[$vm].enabled' <<<"$INVENTORY" >/dev/null || { echo "$VM is disabled in inventory; enable and deploy its host first" >&2; exit 1; }
HOST=$(jq -r --arg vm "$VM" '.vms[$vm].host' <<<"$INVENTORY")
ADDR=$(jq -r --arg host "$HOST" '.hosts[$host].ip.infra' <<<"$INVENTORY")
EXPECTED=$(jq -r --arg host "$HOST" '.hosts[$host].hostKey' <<<"$INVENTORY")
DEST="${SSH_USER:-jurre}@$ADDR"
OPTS=(-o BatchMode=yes -o ConnectTimeout=10)
[ -n "${JUMP:-}" ] && OPTS+=(-J "$JUMP")
ACTUAL=$(ssh "${OPTS[@]}" "$DEST" 'cat /etc/ssh/ssh_host_ed25519_key.pub' | awk '{print $1" "$2}')
[ "$ACTUAL" = "$EXPECTED" ] || { echo "$HOST: SSH host key differs from inventory" >&2; exit 1; }
printf -v UNIT '%q' "microvm@$VM.service"
case "$ACTION" in
  logs) ssh "${OPTS[@]}" "$DEST" "sudo -n journalctl -u $UNIT -n 100 --no-pager" ;;
  *) ssh "${OPTS[@]}" "$DEST" "sudo -n systemctl $ACTION $UNIT --no-pager" ;;
esac
