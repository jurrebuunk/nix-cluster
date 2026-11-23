# k3s cluster (PLAN step 4)

## Status — 2026-11-23

**Running on 4 of 5 VMs.** k3s 1.35.8 (nixpkgs 26.05). `hgd1-k8m02` waits for
VT-x on hv02; until it joins, etcd has 2 members and **no fault tolerance**:
stopping either server stops the API. Do not restart a server VM until then.

| VM | Host (zone) | Role | K8S IP | Status |
| --- | --- | --- | --- | --- |
| hgd1-k8m01 | hgd1-hv01 | server (etcd), bootstrap | 10.10.40.11 | Ready |
| hgd1-k8m02 | hgd1-hv02 | server (etcd) | 10.10.40.12 | waits for hv02 VT-x |
| hgd1-k8m03 | hgd1-hv03 | server (etcd) | 10.10.40.13 | Ready |
| hgd1-k8w01 | hgd1-hv01 | agent | 10.10.40.21 | Ready |
| hgd1-k8w02 | hgd1-hv03 | agent | 10.10.40.22 | Ready |

Verified: pod-to-pod ping across all node pairs, cluster DNS, internet, Ceph
monitors and `s3.lan.buunk.org` from pods on every node; `kubectl` from the
laptop over WARP through `k8s.lan.buunk.org`; a rolling restart of `k8w01`
(new boot, same node identity, no password rejection); kernel RBD map, 8 MiB
write/read-back and unmap from a VM against Ceph 20 (Linux 7.3 guest kernel).

Remaining for "done": k8m02 joins (3 etcd members), `bootstrapServer = null`,
and a server restart without losing the API (see below).

## What the cluster offers the workloads repo

An empty cluster plus a kubeconfig; the workloads repo does not depend on this
flake.

- API: `https://k8s.lan.buunk.org:6443` (VIP `10.10.40.10`), reachable with
  WARP connected (not from USERS without WARP).
- Node label `topology.kubernetes.io/zone=<hypervisor>` for spreading.
- Built-ins: CoreDNS, metrics-server, `local-path` StorageClass. Traefik and
  ServiceLB are disabled: ingress and load balancers (VLAN 40 `.200–.249`,
  network/PLAN.md) come from the workloads repo.
- ConfigMap `kube-system/hgd1-ceph`: `fsid`, `monitors` (v1 `ip:6789` list)
  and `s3Endpoint`, generated from `inventory.nix` for ceph-csi. Nodes load
  `rbd` and `ceph` and reach the storage VLAN directly.
- Pods `10.42.0.0/16`, services `10.43.0.0/16` (k3s defaults), flannel VXLAN
  over the `k8s` NIC.
- Servers are schedulable (no taint): hv02 only has a server, and replicated
  databases need a node in each zone.

## Kubeconfig

```sh
scripts/kubeconfig.sh            # writes ~/.kube/hgd1.yaml (mode 600), context hgd1
nix develop                      # kubectl, KUBECONFIG defaults to ~/.kube/hgd1.yaml
kubectl get nodes -L topology.kubernetes.io/zone
```

The file holds the cluster-admin client certificate: never commit or paste it.
The script checks the server VM's SSH host key against `inventory.nix` first.

## Design

| Piece | Where |
| --- | --- |
| Join/API address: keepalived VIP on the servers, unicast VRRP v3, follows a server whose apiserver answers | `modules/microvm/guest/k3s/api-vip.nix` |
| k3s flags, node IP/label, kubelet config, persistent node password | `modules/microvm/guest/k3s/default.nix` |
| Ports on the `k8s` NIC only (10250, 8472/udp; servers 6443, 2379–2380, VRRP from peer servers) | `modules/microvm/guest/k3s/firewall.nix` |
| Ceph kernel modules and `hgd1-ceph` ConfigMap | `modules/microvm/guest/k3s/ceph.nix` |
| Tokens: decrypted per role on the host, shared read-only over virtiofs | `modules/microvm/host/k3s-secrets.nix`, `lib/k3s.nix` |
| API name, VIP, VRRP id, bootstrap server | `inventory.nix` → `k3s` |

- **Tokens:** `secrets/k3s-server-token.age` and `k3s-agent-token.age`
  (laptop + 3 hosts). Hosts write them as plain files under
  `/run/k3s-secrets/<role>/`; server VMs see both, agents only the agent token.
  Adding a VM needs no re-keying.
- **Bootstrap:** `k3s.bootstrapServer` gets `--cluster-init`; every other node
  joins `https://10.10.40.10:6443`. Once all three servers are members, set it
  to `null` so a rebuilt k8m01 rejoins instead of starting a second cluster.
- **Persistence:** the VM root is tmpfs. All k3s/etcd/containerd state is under
  `/var/lib` (NVMe image); `/etc/rancher/node` links to
  `/var/lib/rancher/node` (otherwise the servers reject a rebooted node's new
  password); container logs go to `/var/lib/kubelet-pod-logs`.
- **etcd snapshots:** every 6 h, 20 kept, in
  `/var/lib/rancher/k3s/server/db/snapshots` on each server. Not yet copied
  off-host (later: S3 on Ceph).
- **Node labels** apply at registration only. Moving a VM means deleting the
  node and letting it rejoin.

## Operate

Host deploys install new VM runners but never restart a VM. Boot them with the
rolling script, which refuses to start unless every enabled VM is a Ready node:

```sh
scripts/k3s-roll.sh                   # all enabled VMs, agents first
scripts/k3s-roll.sh hgd1-k8w01        # one VM
```

Per VM: drain (`--ignore-daemonsets --delete-emptydir-data`, 5 min), restart
via `vm.sh`, wait for a new boot ID to be Ready (10 min), uncordon. Bare pods
without a controller block the drain on purpose. On failure the node stays
cordoned; fix it, then `kubectl uncordon <vm>`.

Add a VM: inventory entry, `enabled = true`, deploy its host, pin `hostKey`
from the host journal (`VM_HOST_KEY` line, VMS.md), commit.

## Finish after hv02 VT-x

1. `sudo ceph osd set noout`, shut down hv02, enable Intel virtualization in its
   BIOS, boot, check `/dev/kvm`, `sudo ceph osd unset noout`, wait for
   HEALTH_OK.
2. `hosts.hgd1-hv02.kvmAvailable = true` and `vms.hgd1-k8m02.enabled = true`;
   commit, `scripts/deploy.sh hgd1-hv02 switch`, pin its `hostKey`.
3. Check 3 etcd members: `kubectl get nodes` shows 3 `control-plane,etcd`.
4. `k3s.bootstrapServer = null`; commit, deploy hv01, then
   `scripts/k3s-roll.sh hgd1-k8m01` while running `kubectl get nodes` in a loop:
   the API must stay up through the VIP.
