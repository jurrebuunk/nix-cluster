# Recovery

What to do when something is broken. Start with the symptom.

## I can't reach anything

1. Is WARP connected? `warp-cli status`. Reconnect, or disconnect and use the
   site network directly if you're on the users VLAN.
2. Do the tunnels run? The Zero Trust dashboard (Networks → Tunnels →
   `hgd1-admin`) shows the connectors. With zero healthy connectors, all three
   hosts are down or offline.
3. **At the site, without WARP:** plug into switch port 1 (mgmt, DHCP
   `10.10.10.100–199`). From there everything internal is reachable,
   including `ssh root@10.10.10.1`.
4. **Router dead:** use the OPNsense console (monitor and keyboard). Restore
   the latest `config.xml` backup from
   `~/.local/state/nix-cluster/network-rollout/` if needed.

## A deploy broke a host

- **Still reachable:** `ssh jurre@<host> 'sudo nixos-rebuild switch --rollback'`.
- **Not reachable:** console, then the previous generation in the
  systemd-boot menu.
- Afterwards revert the commit and deploy the fixed version. The host's
  rollback doesn't change the repo.

For risky network changes, arm the self-reverting guard *before* deploying
(see [Building the network from scratch](../network/bootstrap.md#n5-moving-a-host-to-its-static-addresses)).

## A host is down

The other two keep everything running:

- Ceph: degraded but serving; S3 keeps working through the VIP.
- k3s: workloads move once the node is `NotReady` for a while. With all three
  servers in the cluster, the API stays up.
- Remote access: the other connectors carry it.

Bring it back, then check: SSH works, its monitor is in quorum, its OSD is up,
its VMs are Ready. Ceph catches the returning OSD up by itself.

## Ceph is not HEALTH_OK

```sh
sudo ceph health detail
```

| Message | Meaning |
| --- | --- |
| `noout flag(s) set` | Someone forgot `ceph osd unset noout` after maintenance |
| `1 osds down` / `Degraded data redundancy` | A host or disk is out; data is on two copies until it returns |
| `mon ... down, quorum ...` | One monitor is gone; fine while two are in quorum |
| `clock skew detected` | Check chrony on that host; monitors need closely synced clocks |
| `nearfull` / `full` | Delete data or add capacity; at full, writes stop |

With two hosts down, I/O stops until one returns. Don't force anything; bring
a host back.

## A disk failed

- **HDD:** that host's OSD goes down; data stays on the other two copies. Mark
  it out and replace the disk ([Maintenance](maintenance.md#disk-replacement-hdd)).
- **NVMe:** the host is gone: OS, Ceph monitor store and keyrings, and the
  local disks of its VMs. Reinstall ([Hosts](../hosts/index.md#reinstalling-a-host)),
  re-add its Ceph monitor and OSD, and let the VMs rejoin k3s as new nodes
  (`kubectl delete node` the old ones first).

## The S3 endpoint doesn't answer

```sh
for h in 11 12 13; do ssh jurre@10.10.20.$h 'hostname; ip -br addr show br-stor; systemctl is-active haproxy keepalived'; done
```

- **No host has `10.10.30.10`:** no proxy passes the health check. Usually the
  certificate: `systemctl status acme-s3.lan.buunk.org` and its logs.
- **Two hosts have it:** the hosts can't see each other's VRRP packets on the
  storage VLAN. Check the switch ports (VLAN 30 tagged) and the host firewall.
- **VIP fine, requests fail:** check `sudo ceph -s` and the RGW services.

## A k3s node won't come back

```sh
kubectl describe node <node>
scripts/vm.sh <vm> status
scripts/vm.sh <vm> logs
ssh jurre@<vm-ip> 'sudo journalctl -u k3s -b --no-pager | tail -50'
```

- **"Node password rejected":** `/etc/rancher/node/password` changed. It should
  link to `/var/lib/rancher/node`; check that symlink. If the node was really
  rebuilt, `kubectl delete node <node>` and let it register again.
- **Token errors:** the host must have decrypted the tokens:
  `ssh jurre@<host> 'sudo ls -l /run/k3s-secrets/*'`.
- **Left cordoned by `k3s-roll.sh`:** fix the cause, then `kubectl uncordon`.

## Total loss of the site

The rebuild order, each step depending on the previous one:

1. Network: [Building the network from scratch](../network/bootstrap.md),
   or restore the router and switch from their config backups.
2. NixOS on the three hosts, then deploy this repo
   ([Hosts](../hosts/index.md#reinstalling-a-host)). New host keys mean
   re-encrypting the secrets.
3. Ceph: a new cluster with `scripts/ceph-bootstrap.sh`, or restore the
   cluster identity from the encrypted keyring backups if the HDDs survived.
4. Remote access works again as soon as a host has the tunnel secret.
5. VMs and k3s come up with the hosts; the first server bootstraps a new
   cluster (set `k3s.bootstrapServer` back to it).
6. Workloads from the workloads repo, then data from backups.

Data that only existed in Ceph or on VM disks is only as safe as its backups.
