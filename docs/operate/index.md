---
icon: lucide/heart-pulse
---

# Operate

Running the site day to day. Commands run from the repo root on the laptop
with WARP connected, unless they say "on a host".

## Health check

The quick version, through the [Platform API](../concepts/api.md):

```sh
labctl status
```

The same checks by hand:

```sh
# Hosts: running, no failed units
for h in 11 12 13; do
  ssh jurre@10.10.20.$h 'echo "$(hostname): $(systemctl is-system-running)"; systemctl --failed --no-legend --no-pager'
done

# Ceph
ssh jurre@10.10.20.11 'sudo ceph -s'

# S3 VIP: exactly one host has 10.10.30.10
for h in 11 12 13; do ssh jurre@10.10.20.$h 'ip -br addr show br-stor | grep -q 10.10.30.10 && hostname'; done

# Kubernetes
kubectl get nodes -L topology.kubernetes.io/zone
kubectl get pods -A | grep -v -E 'Running|Completed'

# Remote access: three tunnel connectors
for h in 11 12 13; do ssh jurre@10.10.20.$h 'systemctl is-active "cloudflared-tunnel-*"'; done

# Monitoring: failing probes and down scrape targets (both should print nothing)
curl -s http://mon.lan.buunk.org:8428/api/v1/query --data-urlencode 'query=probe_success == 0 or up == 0' | jq -r '.data.result[].metric | "\(.job) \(.instance)"'
```

**Healthy means:**

- [x] every host is `running` with no failed units;
- [x] Ceph is `HEALTH_OK`, 3 monitors in quorum, `3 osds: 3 up, 3 in`;
- [x] exactly one host owns the S3 VIP;
- [x] all nodes `Ready`, no stuck pods;
- [x] all tunnel services `active`;
- [x] no failing probes or down targets in [monitoring](../concepts/monitoring.md).

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
| Monthly | SMART on every HDD (`smartctl -a`), disk usage (`ceph df`), [update dependencies](../how-to/update-dependencies.md) |
| Every few months | Decrypt the latest backups as a restore test; check remote access with one host stopped |
| Yearly | Rotate Cloudflare and S3 credentials; review the Gateway rules |

## State outside Git

| What | Where |
| --- | --- |
| Router and switch backups (taken by `hgd1-network`), switch SSH config | `~/.local/state/nix-cluster/network-rollout/` (mode 0600) |
| Encrypted Ceph keyring backups | `~/.local/state/nix-hgd1-cluster/ceph-bootstrap/` |
| Encrypted ACME/TLS backups | `~/.local/state/nix-hgd1-cluster/s3-ha/` |
| Kubeconfig | `~/.kube/hgd1.yaml` |
| API token | `~/.config/labctl/token` |
| My S3 keys | `/root/jurre-s3-credentials.json` on hv01 |
| Tunnel credentials | Password manager, plus `secrets/cloudflared-tunnel.age` |

Back these up off the laptop too. The repo can be cloned again; these can't.
