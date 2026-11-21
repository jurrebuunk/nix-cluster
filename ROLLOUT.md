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

1. N1: OPNsense base (DNS, NTP, hostname, backup).
2. N2: VLAN interfaces 20/40/100, DHCP on 10 and 100.
3. N3: switch VLANs and port roles. Hypervisor ports stay **untagged 10** for
   now so the hosts keep their temporary leases.
4. N4: firewall rules; the temporary WAN rules stay.

Meanwhile, start the long SMART tests (each takes a few hours; Ceph waits for
them):

```sh
for ip in <hv01-lease> <hv02-lease> <hv03-lease>; do
  ssh -J "$JUMP" jurre@$ip 'sudo smartctl -t long $(ls /dev/disk/by-id/ata-HGST_* | grep -v part)'
done
```

## C. Move the hypervisors (network plan N5, one host at a time)

Deploying also renames the host (`pveN` → `hgd1-hvNN`) and installs the Ceph
module, which stays idle until part E.

For `hgd1-hv01` (then `hv02`, then `hv03`):

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

**If the host does not come back:** switch port back to untagged 10, then at
its console choose the previous generation in the systemd-boot menu. It boots
with DHCP and gets a `10.10.10.x` lease again.

After all three: the hosts ping each other on the storage VLAN:

```sh
ssh -J "$JUMP" jurre@10.10.20.11 'ping -c2 10.10.30.12; ping -c2 10.10.30.13'
```

## D. Verify the network (network plan N6)

Inter-VLAN policy, internet from the hosts (`nix build` from the cache), and
one reboot of OPNsense and the switch.

## E. Ceph (PLAN step 2)

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
| `osd` | Shows each HDD and its SMART health, asks for `wipe`, zaps it and creates a BlueStore OSD on LVM (`osd.0–2`), activated without tmpfs so it survives reboots. |
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

## F. Remote access and closing bootstrap WAN management (network plan N7)

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
