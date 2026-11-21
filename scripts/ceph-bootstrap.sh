#!/usr/bin/env bash
# Remote scripts are single-quoted on purpose: they expand on the host; run()
# quotes its arguments on the laptop side on purpose.
# shellcheck disable=SC2016,SC2029
# One-time Ceph cluster bootstrap, run from the laptop after every host has been
# deployed with modules/ceph.nix. Based on the nixpkgs test
# nixos/tests/ceph-multi-node-bluestore.nix (manual deployment).
#
# Each phase is skipped when its result already exists, so the script can be
# re-run after a failure. The OSD phase WIPES each host's HDD from inventory.nix
# and asks for confirmation first.
#
# Usage: scripts/ceph-bootstrap.sh [check|mon|mgr|osd|pools|rgw|all]
#
# SSH goes to each host's infra IP; Ceph itself uses the storage IPs.
# Environment: JUMP=<user@addr> to reach the hosts through an SSH jump host.
set -euo pipefail

command -v jq >/dev/null || exec nix shell nixpkgs#jq -c "$0" "$@"
cd "$(git rev-parse --show-toplevel)"

SSH_USER="${SSH_USER:-jurre}"
PHASE="${1:-all}"

INVENTORY=$(nix eval --json --file inventory.nix)
mapfile -t HOSTS < <(jq -r '.hosts | keys[]' <<<"$INVENTORY")
FSID=$(jq -r .ceph.fsid <<<"$INVENTORY")
FIRST="${HOSTS[0]}"

field() { jq -r ".hosts[\"$1\"].$2" <<<"$INVENTORY"; }
ip_of() { field "$1" ip.infra; }
storage_ip_of() { field "$1" ip.storage; }

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10)
[ -n "${JUMP:-}" ] && SSH_OPTS+=(-J "$JUMP")

# Run a bash script (read from stdin) as root on a host; extra args become $1, $2, ...
on() {
  local host="$1"; shift
  ssh "${SSH_OPTS[@]}" "$SSH_USER@$(ip_of "$host")" sudo bash -s -- "$@"
}

# Run a bash script (given as an argument) as root on a host, leaving stdin
# free for data; extra args become $1, $2, ...
run() {
  local host="$1" script="$2"; shift 2
  ssh "${SSH_OPTS[@]}" "$SSH_USER@$(ip_of "$host")" \
    "sudo bash -c $(printf '%q' "$script") bash $(printf '%q ' "$@")"
}

say() { printf '\n==> %s\n' "$*"; }

preflight() {
  say "Preflight: config, storage network, clocks"
  local h peers=()
  for h in "${HOSTS[@]}"; do peers+=("$(storage_ip_of "$h")"); done
  for h in "${HOSTS[@]}"; do
    on "$h" "$FSID" "$h" "${peers[@]}" <<'EOF'
fsid="$1"; name="$2"; shift 2
fail() { echo "$(hostname): $*" >&2; exit 1; }
[ "$(hostname)" = "$name" ] || fail "expected hostname $name; deploy this host first"
grep -Eq "^fsid *= *$fsid$" /etc/ceph/ceph.conf || fail "ceph.conf missing or wrong fsid; deploy first"
ip -br addr show br-stor | grep -q UP || fail "br-stor is not up"
for peer in "$@"; do
  ping -c 2 -W 2 -I br-stor "$peer" >/dev/null || fail "no reply from $peer on the storage VLAN"
done
offset=$(chronyc -c tracking | cut -d, -f5)
awk -v o="$offset" 'BEGIN { exit !(o < 0.05 && o > -0.05) }' || fail "clock offset ${offset}s; wait for chrony to sync"
echo "$(hostname): ok (storage reachable, clock offset ${offset}s)"
EOF
  done
}

phase_mon() {
  local h ip
  if on "$FIRST" <<<'test -e /etc/ceph/ceph.client.admin.keyring'; then
    say "mon: admin keyring exists on $FIRST, skipping key generation"
  else
    say "mon: generating keyrings and monmap on $FIRST"
    local addvs=()
    for h in "${HOSTS[@]}"; do
      ip=$(storage_ip_of "$h")
      addvs+=(--addv "$h" "[v2:$ip:3300,v1:$ip:6789]")
    done
    on "$FIRST" "$FSID" "${addvs[@]}" <<'EOF'
fsid="$1"; shift
install -d -o ceph -g ceph -m 0700 /var/lib/ceph/bootstrap-mon
cd /var/lib/ceph/bootstrap-mon
sudo -u ceph ceph-authtool --create-keyring mon.keyring --gen-key -n mon. --cap mon 'allow *'
ceph-authtool --create-keyring /etc/ceph/ceph.client.admin.keyring --gen-key -n client.admin \
  --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow *' --cap mgr 'allow *'
chmod 0600 /etc/ceph/ceph.client.admin.keyring
sudo -u ceph ceph-authtool mon.keyring --import-keyring /etc/ceph/ceph.client.admin.keyring
sudo -u ceph monmaptool --create "$@" --fsid "$fsid" monmap
EOF
  fi

  # Copy the bootstrap material to the other hosts through the laptop.
  local f
  for h in "${HOSTS[@]:1}"; do
    for f in /var/lib/ceph/bootstrap-mon/mon.keyring /var/lib/ceph/bootstrap-mon/monmap /etc/ceph/ceph.client.admin.keyring; do
      run "$FIRST" 'cat "$1"' "$f" | run "$h" '
install -d -o ceph -g ceph -m 0700 /var/lib/ceph/bootstrap-mon
cat > "$1.tmp"
chmod 0600 "$1.tmp"
case "$1" in /var/*) chown ceph:ceph "$1.tmp" ;; esac
mv "$1.tmp" "$1"' "$f"
    done
  done

  for h in "${HOSTS[@]}"; do
    say "mon: creating mon.$h"
    on "$h" "$h" <<'EOF'
id="$1"
dir=/var/lib/ceph/mon/ceph-$id
if [ -e "$dir/done" ]; then echo "mon.$id already exists"; else
  sudo -u ceph ceph-mon --mkfs -i "$id" \
    --monmap /var/lib/ceph/bootstrap-mon/monmap --keyring /var/lib/ceph/bootstrap-mon/mon.keyring
  sudo -u ceph touch "$dir/done"
  # ceph-mon reads its key from here; the module only starts it once this exists.
  [ -e "$dir/keyring" ] || sudo -u ceph cp /var/lib/ceph/bootstrap-mon/mon.keyring "$dir/keyring"
fi
systemctl start "ceph-mon-$id"
EOF
  done

  say "mon: waiting for quorum"
  on "$FIRST" "${#HOSTS[@]}" <<'EOF'
for _ in $(seq 60); do
  n=$(timeout 10 ceph quorum_status -f json 2>/dev/null | jq '.quorum_names | length' || echo 0)
  [ "$n" = "$1" ] && { ceph mon stat; exit 0; }
  sleep 5
done
echo "mons did not reach quorum" >&2; exit 1
EOF
  on "$FIRST" <<<'ceph config set mon auth_allow_insecure_global_id_reclaim false'

  # The bootstrap material is no longer needed; the admin keyring stays.
  for h in "${HOSTS[@]}"; do
    on "$h" <<<'rm -rf /var/lib/ceph/bootstrap-mon'
  done
}

phase_mgr() {
  local h
  for h in "${HOSTS[@]}"; do
    say "mgr: mgr.$h"
    on "$h" "$h" <<'EOF'
id="$1"
dir=/var/lib/ceph/mgr/ceph-$id
install -d -o ceph -g ceph "$dir"
if [ ! -s "$dir/keyring" ]; then
  ceph auth get-or-create "mgr.$id" mon 'allow profile mgr' osd 'allow *' mds 'allow *' > "$dir/keyring.tmp"
  chown ceph:ceph "$dir/keyring.tmp"; mv "$dir/keyring.tmp" "$dir/keyring"; sync
fi
systemctl start "ceph-mgr-$id"
EOF
  done
}

phase_osd() {
  local h
  say "osd: these disks will be WIPED:"
  for h in "${HOSTS[@]}"; do
    printf '  %s  osd.%s  %s\n' "$h" "$(field "$h" osd.id)" "$(field "$h" hdd)"
  done
  for h in "${HOSTS[@]}"; do
    on "$h" "$(field "$h" hdd)" "$(field "$h" osd.id)" <<'EOF'
disk="$1"; id="$2"
[ -e "/var/lib/ceph/osd/ceph-$id/keyring" ] && { echo "$(hostname): osd.$id already exists"; exit 0; }
[ -b "$disk" ] || { echo "$(hostname): $disk not found" >&2; exit 1; }
dev=$(readlink -f "$disk")
if lsblk -no MOUNTPOINTS "$dev" | grep -q .; then echo "$(hostname): $dev has mounted filesystems" >&2; exit 1; fi
case "$(findmnt -no SOURCE /)" in "$dev"*) echo "$(hostname): $dev is the root disk" >&2; exit 1 ;; esac
echo "--- $(hostname) $disk -> $dev"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MODEL,SERIAL "$dev"
smartctl -H "$dev" | grep -i 'overall-health\|SMART Health' || true
EOF
  done

  local answer
  read -r -p $'\nType "wipe" to wipe these HDDs and create the OSDs: ' answer
  [ "$answer" = "wipe" ] || { echo "aborted"; exit 1; }

  local bootstrap
  bootstrap=$(on "$FIRST" <<<'ceph auth get client.bootstrap-osd')

  for h in "${HOSTS[@]}"; do
    say "osd: osd.$(field "$h" osd.id) on $h"
    printf '%s\n' "$bootstrap" | run "$h" '
install -d -m 0700 /var/lib/ceph/bootstrap-osd
cat > /var/lib/ceph/bootstrap-osd/ceph.keyring
chmod 0600 /var/lib/ceph/bootstrap-osd/ceph.keyring'
    on "$h" "$(field "$h" hdd)" "$(field "$h" osd.id)" "$(field "$h" osd.uuid)" <<'EOF'
disk="$1"; id="$2"; uuid="$3"
if [ ! -e "/var/lib/ceph/osd/ceph-$id/keyring" ]; then
  ceph-volume lvm zap --destroy "$disk"
  ceph-volume lvm prepare --objectstore bluestore --no-systemd \
    --osd-id "$id" --osd-fsid "$uuid" --data "$disk"
  # Re-activate without tmpfs so the OSD directory persists across reboots.
  ceph-volume lvm deactivate "$id" "$uuid"
  ceph-volume lvm activate --no-tmpfs --no-systemd "$id" "$uuid"
  sync
fi
rm -f /var/lib/ceph/bootstrap-osd/ceph.keyring
systemctl start "ceph-osd-$id"
EOF
  done

  say "osd: waiting for all OSDs up and in"
  on "$FIRST" "${#HOSTS[@]}" <<'EOF'
for _ in $(seq 60); do
  s=$(ceph osd stat -f json)
  [ "$(jq .num_up_osds <<<"$s")" = "$1" ] && [ "$(jq .num_in_osds <<<"$s")" = "$1" ] && { ceph osd tree; exit 0; }
  sleep 5
done
echo "OSDs did not come up" >&2; exit 1
EOF
}

phase_pools() {
  say "pools: k8s (RBD) and mgr modules"
  on "$FIRST" <<'EOF'
ceph osd pool ls | grep -qx k8s || { ceph osd pool create k8s; rbd pool init k8s; }
ceph mgr module enable prometheus
ceph osd pool ls detail
EOF
}

phase_rgw() {
  local h
  for h in "${HOSTS[@]}"; do
    say "rgw: client.rgw.$h"
    on "$h" "rgw.$h" <<'EOF'
id="$1"
dir=/var/lib/ceph/radosgw/ceph-$id
install -d -o ceph -g ceph "$dir"
if [ ! -s "$dir/keyring" ]; then
  ceph auth get-or-create "client.$id" osd 'allow rwx' mon 'allow rw' > "$dir/keyring.tmp"
  chown ceph:ceph "$dir/keyring.tmp"; mv "$dir/keyring.tmp" "$dir/keyring"; sync
fi
systemctl start "ceph-rgw-$id"
EOF
  done
}

preflight
case "$PHASE" in
  check) exit 0 ;;
  mon) phase_mon ;;
  mgr) phase_mgr ;;
  osd) phase_osd ;;
  pools) phase_pools ;;
  rgw) phase_rgw ;;
  all) phase_mon; phase_mgr; phase_osd; phase_pools; phase_rgw ;;
  *) echo "unknown phase: $PHASE" >&2; exit 1 ;;
esac

say "Status"
on "$FIRST" <<<'ceph -s'
