---
icon: lucide/life-buoy
---

# Troubleshooting

Find the symptom, follow the steps. For a broken deploy, see
[Roll back](../how-to/roll-back.md).

## No access

1. **WARP:** `warp-cli status`. Reconnect; on the users VLAN at home,
   disconnect it and use the site network directly.
2. **Tunnel:** Zero Trust dashboard → Networks → Tunnels → `hgd1-admin`. Zero
   healthy connectors means all three hosts are down or offline.
3. **At the site without WARP:** switch port 1 (mgmt, DHCP). Everything
   internal is reachable from there, including `ssh root@10.10.10.1`.
4. **Router dead:** the OPNsense console. Restore the latest `config.xml`
   from `~/.local/state/nix-cluster/network-rollout/` if needed.

## Host down

The other two keep the site running:

- Ceph is degraded but serving; S3 keeps working through the VIP.
- k3s reschedules workloads once the node has been `NotReady` for a while.
  With three servers, the API stays up.
- Remote access uses the other connectors.

Bring it back (console, power), then check: SSH works, its monitor is in
quorum, its OSD is `up`, its VMs are Ready. Ceph catches up by itself.

## Ceph not healthy

```sh
sudo ceph health detail
```

| Message | Meaning and fix |
| --- | --- |
| `noout flag(s) set` | Maintenance flag left on: `sudo ceph osd unset noout` |
| `osds down`, `Degraded data redundancy` | A host or disk is out; data is on two copies until it returns |
| `mon … down, quorum …` | One monitor is gone; fine while two are in quorum |
| `clock skew detected` | Check chrony on that host (`chronyc sources`) |
| `nearfull` / `full` | Delete data or add capacity; at `full`, writes stop |

With two hosts down, I/O stops until one returns. Don't force anything;
bring a host back.

## S3 not answering

```sh
for h in 11 12 13; do ssh jurre@10.10.20.$h 'hostname; ip -br addr show br-stor; systemctl is-active haproxy keepalived'; done
```

| You see | Likely cause |
| --- | --- |
| No host has `10.10.30.10` | No proxy passes the health check; usually the certificate. Check `systemctl status acme-s3.lan.buunk.org` and its logs |
| Two hosts have it | They can't see each other's VRRP on the storage VLAN; check the switch ports (VLAN 30 tagged) and host firewalls |
| VIP fine, requests fail | Ceph or the gateways: `sudo ceph -s`, `systemctl status ceph-rgw-*` |

## k3s node not ready

```sh
kubectl describe node <node>
scripts/vm.sh <vm> status
scripts/vm.sh <vm> logs
ssh jurre@<vm-ip> 'sudo journalctl -u k3s -b --no-pager | tail -50'
```

| Symptom | Fix |
| --- | --- |
| `Node password rejected` | `/etc/rancher/node` must link to `/var/lib/rancher/node`. If the node was really rebuilt, `kubectl delete node <node>` and let it register again |
| Token or auth errors | The host must have the tokens: `ssh jurre@<host> 'sudo ls -l /run/k3s-secrets/*'` |
| VM not running, host has no `/dev/kvm` | VT-x is off in the BIOS |
| Left `SchedulingDisabled` by `k3s-roll.sh` | Fix the cause, then `kubectl uncordon <node>` |

## API unreachable

1. Which server has the VIP? `ssh jurre@10.10.40.11 'ip -br addr show k8s'`
   (and `.13`). It shows `10.10.40.10/32` on the owner.
2. No owner: no server's API answers. Check `k3s` on the servers.
3. With only two servers, both must run; one down means no etcd quorum.

## Disk failed

- **HDD:** its OSD goes down, data stays on two copies.
  [Disk replacement](disk-replacement.md).
- **NVMe:** the host is gone, including its Ceph monitor and its VMs' disks.
  [Disaster recovery → Reinstall a host](disaster-recovery.md#reinstall-a-host).
