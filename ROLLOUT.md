# Rollout at home: network, hosts, Ceph, remote access

The order of work for bringing the site up. Parts marked **(you)** are by hand;
the rest is done by Claude over SSH from the laptop on the home WiFi (the
OPNsense WAN side), with you watching.

Design: [network/PLAN.md](network/PLAN.md). Facts: [inventory.nix](inventory.nix).

| Host | Old name (DHCP) | Infra (VLAN 20) | Storage (VLAN 30) | Ceph HDD | OSD |
| --- | --- | --- | --- | --- | --- |
| hgd1-hv01 | pve0 | 10.10.20.11 | 10.10.30.11 | `ata-HGST_HTS721010A9E630_JR1004BNK14S5M` | osd.0 |
| hgd1-hv02 | pve1 | 10.10.20.12 | 10.10.30.12 | `ata-HGST_HTS721010A9E630_JR1000D30JXXWF` | osd.1 |
| hgd1-hv03 | pve2 | 10.10.20.13 | 10.10.30.13 | `ata-HGST_HTS721010A9E630_JR1000D30JXYRF` | osd.2 |

Before every deploy: a clean, committed working tree (`scripts/deploy.sh`
refuses otherwise).

## A. Network bootstrap (you)

**Status: done 2026-11-21.** OPNsense WAN is `192.168.2.12`, so `JUMP=root@192.168.2.12`.

Follow [network/BOOTSTRAP.md](network/BOOTSTRAP.md): cabling, OPNsense with WAN
and LAN `10.10.10.1/24`, SSH key access from the WAN side, switch reachable.
Hand over the WAN IP, switch IP/model/user and the port map.

After this the hypervisors have temporary `10.10.10.x` leases (OPNsense →
Services → DHCPv4 → Leases; match on the MACs in `inventory.nix`).

Set for the rest of this runbook:

```sh
export JUMP=root@<opnsense-wan-ip>
```

## B. Router and switch (Claude, network plan N1–N4)

**Status: done 2026-11-21.** N5/N6 completed 2026-11-22. Extended HDD tests
were started after each node's migration reboot and are still pending; do not
reboot the hosts again until those tests finish.

1. N1: OPNsense base (DNS, NTP, hostname, backup).
2. N2: VLAN interfaces 20/40/100, DHCP on 10 and 100.
3. N3: switch VLANs and port roles. Hypervisor ports stay **untagged 10** for
   now so the hosts keep their temporary leases.
4. N4: firewall rules; the temporary WAN rules stay.

After each node's last planned migration reboot, start the long SMART test
(each takes a few hours; Ceph waits for it). A host reboot may abort a test:

```sh
for ip in <hv01-lease> <hv02-lease> <hv03-lease>; do
  ssh -J "$JUMP" jurre@$ip 'sudo smartctl -t long $(ls /dev/disk/by-id/ata-HGST_* | grep -v part)'
done
```

## C. Move the hypervisors (network plan N5, one host at a time)

**Status: done 2026-11-22.** hv01/hv02/hv03 are on ports 5/7/9, respectively,
now native VLAN 20 and tagged VLANs 30/40. Host keys, root/EFI UUIDs and HDD
serials matched inventory. New key-based SSH, storage connectivity, clock sync,
internet and service health passed after each reboot; all rollback markers
were removed and timers disarmed. The procedure below is for future recovery
or a fresh bootstrap, not something to repeat on the live static hosts.

Deploying also renames the host (`pveN` → `hgd1-hvNN`) and installs the Ceph
module, which stays idle until part E.

For `hgd1-hv01` (then `hv02`, then `hv03`):

0. **Prepare the timed recovery guard** on this host (root-only state):
   ```sh
   ssh -J "$JUMP" jurre@10.10.10.<lease> 'sudo sh -c '\''umask 077; mkdir -p /var/lib/n5-rollout/before; readlink -f /run/current-system > /var/lib/n5-rollout/before/current-system; touch /var/lib/n5-rollout/pending'\'''
   ```
   `modules/rollout-safety.nix` returns to that saved boot generation and
   reboots after ten minutes unless confirmed. It cannot repair a kernel that
   fails before systemd starts; the console/previous boot entry remains the
   fallback for that case.
1. **Install the new config for the next boot**, via its temporary lease:
   ```sh
   TARGET=10.10.10.<lease> scripts/deploy.sh hgd1-hv01 boot
   ```
   The script checks that the host key matches `inventory.nix` first.
2. **Schedule the reboot**, then switch the port within the minute:
   ```sh
   ssh -J "$JUMP" jurre@10.10.10.<lease> 'sudo systemd-run --on-active=60 systemctl reboot'
   ```
   Switch port of this host → untagged **20**, tagged **30, 40** (Claude, on
   the switch).
3. **Verify** on the new address:
   ```sh
   ssh -J "$JUMP" jurre@10.10.20.11 \
     'hostname; ip -br addr; networkctl; chronyc sources; systemctl --failed --no-pager'
   ```
   Expected: hostname `hgd1-hv01`, `enp2s0` with `10.10.20.11/24`, `br-stor`
   with `10.10.30.11/24`, `br-k8s` up without an address, chrony using
   `10.10.20.1`, no failed units (Ceph units are skipped, not failed).

4. **Disarm recovery only after checking key-based SSH, addresses, routes,
   clock sync and service health**:
   ```sh
   ssh -J "$JUMP" jurre@10.10.20.11 \
     'sudo rm /var/lib/n5-rollout/pending; sudo systemctl stop n5-rollback.timer'
   ```

**If the host does not come back:** restore its switch port to untagged 10
and wait for the ten-minute guard to restore the old generation and reboot.
It boots with DHCP and gets a `10.10.10.x` lease again. If it failed before
systemd could run the guard, use its console to choose the previous generation
in the systemd-boot menu. Never move another node until this one is confirmed.

After all three: the hosts ping each other on the storage VLAN:

```sh
ssh -J "$JUMP" jurre@10.10.20.11 'ping -c2 10.10.30.12; ping -c2 10.10.30.13'
```

## D. Verify the network (network plan N6)

**Status: done 2026-11-22.** 83/83 probes passed from disposable clients on
MGMT/INFRA/K8S/USERS, including actual host SSH isolation and ingress address
boundaries. OPNsense and Aruba were rebooted; all nodes and Sunshine returned,
and running/startup switch configurations match. Storage reaches all three
nodes at L2 but has no router interface/route. Spare ports 16/18 were restored
to disabled VLAN 999 and test namespaces removed.

Inter-VLAN policy, internet from the hosts (`nix build` from the cache), and
one reboot of OPNsense and the switch.

The original N6 disposable node fixture used `10.10.40.11` before step 3.
That address now belongs to the live VM: do not rerun an old fixture that
aliases it. Pick unused addresses and verify inventory before any future test.

## E. Ceph (PLAN step 2)

**Status: pending disk qualification.** Services/configuration are deployed
but remain gated off without keyrings. No Ceph cluster, pools or buckets have
been initialized. See [CEPH.md](CEPH.md) for disk cautions and S3 access.

Check the SMART results first; any reallocated or pending sectors, or a failed
long test, means that disk does not go into Ceph:

```sh
for h in 11 12 13; do
  ssh -J "$JUMP" jurre@10.10.20.$h 'hostname; sudo smartctl -l selftest -A $(ls /dev/disk/by-id/ata-HGST_* | grep -v part) | grep -E "Extended|Reallocated_Sector|Current_Pending|Offline_Unc"'
done
```

Then:

```sh
scripts/ceph-bootstrap.sh check     # config, storage VLAN reachability, clock sync
scripts/ceph-bootstrap.sh           # all phases (asks you to type "wipe" before the OSDs)
```

| Phase | Result |
| --- | --- |
| `mon` | Mon and admin keyrings and a monmap with all three mons (storage IPs) on `hgd1-hv01`, copied to the others; `ceph-mon-hgd1-hvNN` on every host; waits for quorum; removes the bootstrap material. `/etc/ceph/ceph.client.admin.keyring` stays on every host. |
| `mgr` | `mgr.hgd1-hvNN` on every host (one active, two standby). |
| `osd` | Checks disk serial, mounted/root devices, blank media, current SMART health and a successful extended test within 24 power-on hours; refuses unsafe/incomplete qualification. Then asks for `wipe` and creates BlueStore OSDs on LVM (`osd.0–2`), activated without tmpfs. |
| `pools` | Pool `k8s` (RBD, for k3s later) and the mgr `prometheus` module (port 9283). |
| `rgw` | S3 gateway `client.rgw.hgd1-hvNN` on every host, port 7480; it creates its own pools. |

Every phase skips work that already exists, so re-running is safe. Keyrings are
runtime state on the hosts and never in this repo. Ceph listens only on
`br-stor` (VLAN 30), so it is not reachable from the laptop directly.

### Verify

```sh
ssh -J "$JUMP" jurre@10.10.20.11 'sudo ceph -s; sudo ceph osd tree; sudo ceph osd pool ls'
ssh -J "$JUMP" jurre@10.10.20.11 'curl -s http://10.10.30.12:7480'   # S3 XML reply
```

Expected: `HEALTH_OK` (a few minutes after RGW created its pools), 3 mons in
quorum, 1 active + 2 standby mgrs, `3 osds: 3 up, 3 in`, one OSD per host.

Reboot test, one host at a time, waiting for `HEALTH_OK` in between:

```sh
ssh -J "$JUMP" jurre@10.10.20.11 'sudo ceph osd set noout'
ssh -J "$JUMP" jurre@10.10.20.12 'sudo systemctl reboot'
# wait, then: osd.1 up again, mon hgd1-hv02 back in quorum
ssh -J "$JUMP" jurre@10.10.20.11 'sudo ceph -s'
ssh -J "$JUMP" jurre@10.10.20.11 'sudo ceph osd unset noout'
```

## VM platform (PLAN step 3)

**Done 2026-11-22 while HDD qualification was running.** The platform is deployed
on all hosts, and one empty VM (`hgd1-k8m01`) runs on hv01 at `10.10.40.11`
with storage `10.10.30.21`. Actual VM restart preserved data/SSH identity, and
host deployment left its QEMU PID unchanged. Seven additional checks confirmed
no management SSH bypass through either guest-facing host bridge and no guest
SSH exposure on storage. See [VMS.md](VMS.md) for operations and hv02's pending
BIOS virtualization prerequisite. No k3s services are installed yet.

## F. Remote access and closing bootstrap WAN management (network plan N7)

**Deferred by request.** `remoteAccess.tunnelId` remains null; do not remove
bootstrap WAN management while working on Ceph or the VM platform.

Follow [network/REMOTE-ACCESS.md](network/REMOTE-ACCESS.md): Zero Trust
organisation and tunnel (you, in the dashboard and `cloudflared tunnel login`),
secret and deploy to all three hosts, WARP client settings, OPNsense rule, then
remove only the temporary WAN management rules. Keep the permanent home-WAN
Sunshine forwards and leave the WAN private-network block off (see the network
plan's gaming exception). From then on, no `JUMP` is needed: with WARP
connected, `ssh jurre@10.10.20.11` works from anywhere.

Next: PLAN step 3 (VM platform).

## Daily Ceph operations

```sh
sudo ceph -s                         # health overview
sudo ceph health detail              # explain warnings
sudo ceph osd df tree                # usage per OSD/host
sudo ceph df                         # usage per pool
sudo systemctl status ceph-mon-hgd1-hv01 ceph-mgr-hgd1-hv01 ceph-osd-0 ceph-rgw-rgw.hgd1-hv01
```

Host maintenance: `ceph osd set noout`, update or reboot the host, wait for its
OSD and mon to return, `ceph osd unset noout`. Only one host at a time: with 3
replicas and `min_size 2`, a second host down stops I/O.

Create an S3 user (for example for Cloudreve later):

```sh
sudo radosgw-admin user create --uid=cloudreve --display-name=Cloudreve
```

## Known limits / follow-ups

- Kernel Ceph clients (krbd/CephFS used by ceph-csi in the k3s VMs later) may
  need Linux ≥ 7.0 for Ceph 20.2.4's `aes256k` auth cipher (the nixpkgs Ceph
  test pins `linuxPackages_latest` for this). Hosts run 6.18 but use no kernel
  client. Check this in PLAN step 4.
- RGW is plain HTTP on the storage VLAN; HTTPS for clients comes through the
  k3s ingress (PLAN step 6).
- CephFS (MDS) is not configured yet; add it when an app needs it.
- No Ceph dashboard; monitoring goes through the mgr Prometheus endpoint.
