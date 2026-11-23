# Operations

The day-to-day side of running the site. Every command here runs from the
repo root on the laptop with WARP connected, unless it says "on a host".

## Health check in five minutes

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

# Remote access: three healthy connectors
for h in 11 12 13; do ssh jurre@10.10.20.$h 'systemctl is-active "cloudflared-tunnel-*"'; done
```

**Healthy means:**

- every host is `running` with no failed units;
- Ceph is `HEALTH_OK` with 3 monitors in quorum and `3 osds: 3 up, 3 in`;
- exactly one host owns the S3 VIP;
- all nodes are `Ready` and no pods are stuck;
- all tunnel services are `active`.

## The rules I stick to

1. **One host at a time.** Deploys, reboots, maintenance: finish one host and
   check health before touching the next. Ceph and etcd survive one missing
   host, never two.
2. **Everything goes through the repo.** No manual edits on hosts or VMs;
   they disappear on the next deploy anyway.
3. **Check before deleting or overwriting.** Look at the target first. Disk
   images and Ceph data can't be restored from Git.
4. **Back up the router before changing it.** Export `config.xml` first.
5. **Secrets never in Git, chat or logs.** See [Secrets](secrets.md).

## Runbooks

| Task | Page |
| --- | --- |
| Deploy a change, roll back, update dependencies | [Change and deploy](../hosts/deploy.md) |
| Reboot or service a host, Ceph `noout`, restart VMs | [Maintenance](maintenance.md) |
| Add or rotate a secret, re-key after a host change | [Secrets](secrets.md) |
| Locked out, host won't boot, disk failed, total loss | [Recovery](recovery.md) |
| Add, move or remove a VM | [VMs](../compute/vms.md#adding-moving-and-removing-vms) |
| Restart k3s nodes safely | [k3s](../compute/k3s.md#rolling-restarts) |
| Create an S3 user | [S3](../storage/s3.md#users-and-buckets) |

## Where state lives outside Git

| What | Where |
| --- | --- |
| Router and switch config backups, SSH config for the switch | `~/.local/state/nix-cluster/network-rollout/` (mode 0600) |
| Encrypted Ceph keyring backups | `~/.local/state/nix-hgd1-cluster/ceph-bootstrap/` |
| Encrypted ACME/TLS backups | `~/.local/state/nix-hgd1-cluster/s3-ha/` |
| Kubeconfig | `~/.kube/hgd1.yaml` |
| My S3 keys | `/root/jurre-s3-credentials.json` on hv01 |
| Cloudflare tunnel credentials | Password manager, plus `secrets/cloudflared-tunnel.age` |

Back these up off the laptop too. The repo can be cloned again; these can't.
