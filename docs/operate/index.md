---
icon: lucide/heart-pulse
---

# Operate

Running the site day to day. Commands run on the laptop with WARP connected.
Day to day that means [`labctl`](../how-to/use-the-cli.md): it reaches every
host, VM, Ceph and the monitoring through one authenticated API, so most
checks need no SSH and no `sudo`. SSH is for the few things the API can't do
yet, and for when the API itself is down.

## Health check

```sh
labctl status                                                        # hosts, VMs, nodes, Ceph, VIPs, disks, S3
labctl metrics query 'node_systemd_unit_state{state="failed"} == 1'  # failed units on the hosts
labctl metrics query 'probe_success == 0 or up == 0'                 # failing probes, down scrape targets
labctl metrics query 'cloudflared_tunnel_ha_connections'             # remote access, per host
kubectl get pods -A | grep -v -E 'Running|Completed'                 # workloads (from hgd1-k8s)
```

The two queries that look for problems print `(no data)` when there are none.
`labctl status` prints problems as `warning:` lines on stderr, so a quiet
run is a good sign.

**Healthy means:**

- [x] every host `Up` and on the same `clusterd` version; no failed units;
- [x] every VM `Running`, every node `Ready` (without `SchedulingDisabled`);
- [x] Ceph `HEALTH_OK`, `3/3` OSDs up and in, all PGs clean;
- [x] each VIP has exactly one owner;
- [x] no disk warnings (wear, SMART, fullness) and S3 gateways `3/3`;
- [x] 4 tunnel connections per host;
- [x] no failing probes or down targets in [monitoring](../concepts/monitoring.md), no stuck pods.

??? note "Without the API: the same checks on the hosts"

    When `api.lan.buunk.org` itself is down, check over SSH:

    ```sh
    for h in 11 12 13; do
      ssh jurre@10.10.20.$h 'echo "$(hostname): $(systemctl is-system-running)"; systemctl --failed --no-legend --no-pager'
    done
    ssh jurre@10.10.20.11 'sudo ceph -s'
    for h in 11 12 13; do ssh jurre@10.10.20.$h 'ip -br addr show | grep -E "10.10.(20.10|20.20|30.10)/" && hostname'; done
    for h in 11 12 13; do ssh jurre@10.10.20.$h 'systemctl is-active "cloudflared-tunnel-*" clusterd'; done
    ```

Anything else: [Troubleshooting](troubleshooting.md).

## Ground rules

1. **One host at a time.** Deploys, reboots, maintenance: finish one host and
   check health before the next. Ceph and etcd survive one missing host,
   never two.
2. **Everything goes through the repo.** Manual edits on hosts or VMs vanish
   on the next deploy.
3. **Look before you delete or overwrite.** Disk images and Ceph data can't
   be restored from Git.
4. **Router and switch only through [`hgd1-network`](https://github.com/jurrebuunk/hgd1-network)**, which backs them up first.
5. **Secrets never in Git, chat or logs.**

## Runbooks

<div class="grid cards" markdown>

- :lucide-power: [**Host maintenance**](host-maintenance.md): reboot or service a host safely
- :lucide-router: [**Router and switch**](router-and-switch.md): what's configured, access, reboot impact
- :lucide-hard-drive: [**Disk replacement**](disk-replacement.md): swap a failed HDD
- :lucide-life-buoy: [**Troubleshooting**](troubleshooting.md): find the fix by symptom
- :lucide-siren: [**Disaster recovery**](disaster-recovery.md): reinstall a host, rebuild the site
- :lucide-cable: [**Rebuild the network**](rebuild-network.md): bring the network up from scratch

</div>

## Schedule

| How often | What |
| --- | --- |
| Weekly | The health check above |
| Monthly | `labctl status disk` (fullness, wear, SMART) and `labctl status s3` (buckets, room); `smartctl -a` on a drive that warns; [update dependencies](../how-to/update-dependencies.md) |
| Every few months | Decrypt the latest backups as a restore test; check remote access with one host stopped |
| Yearly | Rotate Cloudflare and S3 credentials; review the Gateway rules |

## State outside Git

| What | Where |
| --- | --- |
| Router and switch backups (taken by `hgd1-network`), switch SSH config | `~/.local/state/nix-cluster/network-rollout/` (mode 0600) |
| Encrypted Ceph keyring backups | `~/.local/state/nix-hgd1-cluster/ceph-bootstrap/` |
| Encrypted ACME/TLS backups | `~/.local/state/nix-hgd1-cluster/s3-ha/` |
| Kubeconfig | `~/.kube/hgd1.yaml` |
| API token | `~/.config/labctl/tokens/hgd1` |
| My S3 keys | `/root/jurre-s3-credentials.json` on hv01 |
| Tunnel credentials | Password manager, plus `secrets/cloudflared-tunnel.age` |

Back these up off the laptop too. The repo can be cloned again; these can't.
