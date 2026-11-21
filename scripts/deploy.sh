#!/usr/bin/env bash
# Deploy one host from this flake.
#
# Usage: scripts/deploy.sh <host> [switch|boot|test|dry-activate]   (default: switch)
#
# Environment:
#   TARGET=<addr>     Connect to this address instead of the inventory's infra IP
#                     (e.g. a temporary 10.10.10.x lease during the network move).
#   JUMP=<user@addr>  SSH jump host, e.g. root@<opnsense-wan-ip> while the laptop
#                     is on the WAN side.
#   ALLOW_DIRTY=1     Deploy uncommitted changes (normally refused).
#
# The host builds its own system (it is the build host) and fetches from the
# binary cache itself; the laptop only evaluates the flake.
set -euo pipefail

command -v jq >/dev/null || exec nix shell nixpkgs#jq -c "$0" "$@"
cd "$(git rev-parse --show-toplevel)"

HOST="${1:?usage: $0 <host> [switch|boot|test|dry-activate]}"
ACTION="${2:-switch}"
SSH_USER="${SSH_USER:-jurre}"

case "$ACTION" in
  switch | boot | test | dry-activate) ;;
  *) echo "unknown action: $ACTION" >&2; exit 1 ;;
esac

INVENTORY=$(nix eval --json --file inventory.nix)
jq -e --arg h "$HOST" '.hosts | has($h)' <<<"$INVENTORY" >/dev/null \
  || { echo "unknown host: $HOST" >&2; exit 1; }
ADDR="${TARGET:-$(jq -r --arg h "$HOST" '.hosts[$h].ip.infra' <<<"$INVENTORY")}"
EXPECTED_KEY=$(jq -r --arg h "$HOST" '.hosts[$h].hostKey' <<<"$INVENTORY")
DEST="$SSH_USER@$ADDR"

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10)
[ -n "${JUMP:-}" ] && SSH_OPTS+=(-J "$JUMP")
export NIX_SSHOPTS="${SSH_OPTS[*]}"

if [ -n "$(git status --porcelain)" ] && [ "${ALLOW_DIRTY:-}" != 1 ]; then
  echo "working tree is not clean; commit first (or ALLOW_DIRTY=1)" >&2
  exit 1
fi

echo "==> $HOST via $DEST${JUMP:+ (jump $JUMP)}: $ACTION @ $(git rev-parse --short HEAD)"

# The host key must match the inventory: agenix secrets are encrypted to it,
# and a mismatch means the wrong machine or a reinstalled one.
ACTUAL_KEY=$(ssh "${SSH_OPTS[@]}" "$DEST" 'cat /etc/ssh/ssh_host_ed25519_key.pub' | awk '{print $1" "$2}')
if [ "$ACTUAL_KEY" != "$EXPECTED_KEY" ]; then
  echo "host key mismatch for $HOST at $ADDR" >&2
  echo "  inventory: $EXPECTED_KEY" >&2
  echo "  actual:    $ACTUAL_KEY" >&2
  exit 1
fi

ACTUAL_NAME=$(ssh "${SSH_OPTS[@]}" "$DEST" hostname)
if [ "$ACTUAL_NAME" != "$HOST" ]; then
  echo "note: $ADDR currently calls itself '$ACTUAL_NAME' (rename takes effect on activation)"
fi

nixos-rebuild "$ACTION" \
  --flake ".#$HOST" \
  --build-host "$DEST" --target-host "$DEST" \
  --sudo --use-substitutes

if [ "$ACTION" = boot ]; then
  echo "==> Installed as next boot entry. Reboot with:"
  echo "    ssh ${JUMP:+-J $JUMP }$DEST 'sudo systemctl reboot'"
fi
