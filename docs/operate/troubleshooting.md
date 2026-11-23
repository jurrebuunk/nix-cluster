---
icon: lucide/life-buoy
---

# Troubleshooting

Find the symptom, follow the steps. Start with `labctl status <part>` and
`labctl logs`: they read every host and VM without SSH. SSH in only for the
fixes that need a shell. For a broken deploy, see
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

`labctl status` shows it as `Unreachable`, its VMs as `Unknown` and any VIP
it held as moved. Bring it back (console, power), then check with
`labctl status host`, `labctl status ceph` (OSD up, no new checks) and
`labctl status node` (its VMs Ready). Ceph catches up by itself.

## Ceph not healthy

```sh
labctl status ceph                       # each check is a warning: line
labctl logs --since 1h 'unit:"ceph-mon"*'   # what the monitors said
```

| Message | Meaning and fix |
| --- | --- |
| `noout flag(s) set` | Maintenance flag left on: `ssh jurre@10.10.20.11 'sudo ceph osd unset noout'` |
| `osds down`, `Degraded data redundancy` | A host or disk is out; data is on two copies until it returns |
| `mon … down, quorum …` | One monitor is gone; fine while two are in quorum |
| `clock skew detected` | `labctl metrics query 'node_timex_offset_seconds'` shows the offset per host and VM; then `chronyc sources` on that host |
| `nearfull` / `full` | `labctl status disk` and `labctl status s3` show what fills up. Delete data or add capacity; at `full`, writes stop |

With two hosts down, I/O stops until one returns. Don't force anything;
bring a host back.

## S3 not answering

```sh
labctl status vip                        # who owns 10.10.30.10
labctl status s3                         # gateways, certificate, room
labctl logs --unit keepalived --since 1h # VIP moves and failing checks
labctl logs --unit haproxy --since 1h
```

| You see | Likely cause |
| --- | --- |
| `s3` owner `<none>` | No proxy passes the health check; usually the certificate. The `CERT` column and `labctl logs --since 1d 'unit:"acme"* error'` tell |
| More than one owner (split brain warning) | They can't see each other's VRRP on the storage VLAN; check the switch ports (VLAN 30 tagged) and host firewalls |
| VIP fine, requests fail | Ceph or the gateways: `labctl status ceph`, the `GATEWAYS` column of `labctl status s3`, `labctl logs --since 1h 'unit:"ceph-rgw"*'` |

## k3s node not ready

```sh
labctl status node                                # Ready, cordoned?
labctl status vm                                  # is the VM itself running?
labctl logs --host <vm> --unit k3s --since 30m    # k3s inside the VM
labctl logs --unit microvm@<vm> --since 1h        # the VM's console, from its host
kubectl describe node <node>                      # conditions and events
labctl vm restart <vm>                            # often the fix; safe and refuses when it isn't
```

| Symptom | Fix |
| --- | --- |
| `Node password rejected` | `/etc/rancher/node` must link to `/var/lib/rancher/node`. If the node was really rebuilt, `kubectl delete node <node>` and let it register again |
| Token or auth errors | The host must have the tokens: `ssh jurre@<host> 'sudo ls -l /run/k3s-secrets/*'` (secrets need a shell) |
| VM not running, host has no `/dev/kvm` | VT-x is off in the BIOS |
| Left `SchedulingDisabled` by a restart | It didn't come back in time and was left cordoned on purpose. Fix the cause, then `kubectl uncordon <node>` |

## API unreachable

1. `labctl status node`: if it answers, the API is up for clusterd and the
   problem is between you and `k8s.lan.buunk.org` (WARP, DNS).
2. Who has the VIP? `labctl logs --unit keepalived --since 1h 'k8s'` shows
   which server entered `MASTER` last. `labctl metrics query
   'probe_success{job="probe-k8s-api"}'` shows whether the hosts reach it.
3. No owner: no server's API answers. `labctl logs --host hgd1-k8m01 --unit k3s
   --since 30m` (and `k8m02`, `k8m03`).
4. etcd needs two of the three servers; with two down, the API stops.

## Monitoring

| You see | Likely cause and fix |
| --- | --- |
| `mon.lan.buunk.org` doesn't answer | No host passes the VIP check. `labctl status host` shows `MetricsDown`/`LogsDown` per host; `labctl metrics` and `labctl logs` keep working through the other hosts' stores |
| A target is `down` | `labctl metrics query 'up == 0'` names it; `labctl logs --unit vmagent --since 1h` says why. On a host, `curl -s 127.0.0.1:8429/api/v1/targets` gives the `lastError`. Router: is `os-node_exporter` running? VMs: was the VM restarted after the monitoring deploy? |
| One copy has fewer series | vmagent is still catching up from its disk buffer; give it a few minutes |
| No logs from a VM | `labctl metrics query 'up{job="vm-node"}'` (is the VM reachable at all?), then `ssh jurre@<vm> systemctl status vector`; it ships over the storage VLAN |
| Router or switch logs missing | Both send to `10.10.20.10:514`; check the syslog settings in [`hgd1-network`](https://github.com/jurrebuunk/hgd1-network) and `show logging` on the switch |
| A disk is missing from SMART | The NVMe ACL is set by udev at boot. Without a reboot: `sudo udevadm trigger --subsystem-match=nvme --action=add`, then restart `prometheus-smartctl-exporter` |

## API

| You see | Likely cause and fix |
| --- | --- |
| `labctl` exits with code 3 | API unreachable: check WARP, then `curl -s https://api.lan.buunk.org/v1/health` |
| `/v1/health` fails | No host passes the VIP check: `systemctl status clusterd keepalived` on each host (this one needs SSH: the API is what's broken) |
| 401 / exit code 4 | Token unknown or revoked; `labctl whoami`, or create a new one ([Tokens](../how-to/use-the-cli.md#tokens)) |
| 403 on an action | The token has scope `read`; actions need at least `operator` |
| 409 on an action | Another action runs (the message names it). Wait, or if its clusterd crashed, the lock frees itself within two minutes |
| 412 on a VM restart | It would be unsafe now; the message says why (a node not Ready, etcd quorum, a pod without a controller). Fix that first |
| A restart ended with the node `SchedulingDisabled` | The VM didn't come back Ready in 10 minutes; it was left cordoned on purpose. Check `labctl logs --unit microvm@<vm> --since 30m`, then `kubectl uncordon` |
| `warning: disks: ceph osds: … EACCES` | The Ceph key lacks `mgr 'allow r'`: `ceph auth caps client.clusterd mon 'allow r' mgr 'allow r'` (it prints the key: send the output to `/dev/null`) |
| `warning: s3: buckets: … 403` | The RGW user `clusterd` is missing its caps, or `secrets/clusterd-s3-admin.age` doesn't match it: `radosgw-admin user info --uid=clusterd` |
| VM restart fails with `Interactive authentication required` | The polkit rule is missing: is `services.clusterd.manageUnitPrefixes` set, and `/etc/polkit-1/rules.d/10-nixos.rules` present? |
| A host shows `Unreachable` in `labctl status` | `clusterd` is down there or port 443 is blocked: `labctl logs --host <host> --unit clusterd --since 1h`, then `systemctl status clusterd` on that host |
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
