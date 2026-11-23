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
4. **Router dead:** the OPNsense console. Restore the latest backup (see
   [`hgd1-network`](https://github.com/jurrebuunk/hgd1-network)) or re-apply its playbooks.

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
   (and `.12`, `.13`). It shows `10.10.40.10/32` on the owner.
2. No owner: no server's API answers. Check `k3s` on the servers
   (`ssh jurre@10.10.40.12` too).
3. etcd needs two of the three servers; with two down, the API stops.

## Monitoring

| You see | Likely cause and fix |
| --- | --- |
| `mon.lan.buunk.org` doesn't answer | No host passes the VIP check. On each host: `systemctl status victoriametrics victorialogs keepalived` |
| A target is `down` | On a host: `curl -s 127.0.0.1:8429/api/v1/targets`; the `lastError` says why. Router: is `os-node_exporter` running? VMs: was the VM restarted after the monitoring deploy? |
| One copy has fewer series | vmagent is still catching up from its disk buffer; give it a few minutes |
| No logs from a VM | `ssh jurre@<vm> systemctl status vector`; it ships over the storage VLAN |
| Router or switch logs missing | Both send to `10.10.20.10:514`; check the syslog settings in [`hgd1-network`](https://github.com/jurrebuunk/hgd1-network) and `show logging` on the switch |
| A disk is missing from SMART | The NVMe ACL is set by udev at boot. Without a reboot: `sudo udevadm trigger --subsystem-match=nvme --action=add`, then restart `prometheus-smartctl-exporter` |

## API

| You see | Likely cause and fix |
| --- | --- |
| `labctl` exits with code 3 | API unreachable: check WARP, then `curl -s https://api.lan.buunk.org/v1/health` |
| `/v1/health` fails | No host passes the VIP check: `systemctl status clusterd keepalived` on each host |
| 401 / exit code 4 | Token unknown or revoked; `labctl whoami`, or create a new one ([Tokens](../how-to/use-the-cli.md#tokens)) |
| 403 on an action | The token has scope `read`; actions need at least `operator` |
| 409 on an action | Another action runs (the message names it). Wait, or if its clusterd crashed, the lock frees itself within two minutes |
| 412 on a VM restart | It would be unsafe now; the message says why (a node not Ready, etcd quorum, a pod without a controller). Fix that first |
| A restart ended with the node `SchedulingDisabled` | The VM didn't come back Ready in 10 minutes; it was left cordoned on purpose. Check `journalctl -u microvm@<vm>` on its host, then `kubectl uncordon` |
| VM restart fails with `Interactive authentication required` | The polkit rule is missing: is `services.clusterd.manageUnitPrefixes` set, and `/etc/polkit-1/rules.d/10-nixos.rules` present? |
| A host shows `unreachable` in `labctl status` | `clusterd` is down there or port 443 is blocked: `systemctl status clusterd` on that host, then `journalctl -u clusterd` |
| `k3s: unreachable` in the status | The ServiceAccount token or CA no longer matches (a rebuilt cluster): recreate `secrets/clusterd-kubeconfig.age` from the `clusterd-token` Secret in namespace `clusterd` |
| Ceph shows `unknown` with an error | `client.clusterd` is missing or `secrets/clusterd-ceph-keyring.age` doesn't match it: `ceph auth get client.clusterd` |
| A new token is rejected after the deploy | `clusterd` didn't restart (secrets are loaded at start): `sudo systemctl restart clusterd` on each host |
| Web UI loads but shows no data | The pod can't reach `10.10.20.20:443` (OPNsense rule in [`hgd1-network`](https://github.com/jurrebuunk/hgd1-network)), or its `operator` token is revoked |
| Metrics or logs empty through the API | Check the stores themselves: [Monitoring](#monitoring) |

## Disk failed

- **HDD:** its OSD goes down, data stays on two copies.
  [Disk replacement](disk-replacement.md).
- **NVMe:** the host is gone, including its Ceph monitor and its VMs' disks.
  [Disaster recovery → Reinstall a host](disaster-recovery.md#reinstall-a-host).
