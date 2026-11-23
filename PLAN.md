# Cluster plan

Plan for turning `hgd1-hv01`, `hgd1-hv02` and `hgd1-hv03` into a NixOS-managed platform that runs
Ceph on the hosts and a 5-VM k3s cluster on top. Nothing below is implemented yet
unless a step says so. Code snippets are sketches, not final config.

## Goals

- All host, storage and VM configuration lives in Nix (this repo).
- k3s VMs are disposable: adding, moving or rebuilding one is a small inventory
  change plus a deploy.
- Ceph on the hosts provides storage for workloads running on k3s.
- Later: a self-built backend for monitoring and small operational actions
  (restart a VM, maintenance), usable from a web UI or a laptop CLI.

## Architecture

```
 laptop: nixos-rebuild / CLI ──┐        web UI ──┐   (backend: later)
                               ▼                 ▼
 ┌──────────────────────────────────────────────────────────────┐
 │ hgd1-hv01..03   NixOS, VLAN 20 host, br-stor (30), br-k8s (40)│
 │  ├ NVMe: host OS, Nix store, VM disks (k3s state, local DBs)  │
 │  ├ HDD:  Ceph OSD                                             │
 │  ├ ceph mon + mgr + osd  [+ rgw (S3), + mds (CephFS)]         │
 │  └ microvm.nix VMs (systemd units microvm@<name>)             │
 └──────────────────────────────────────────────────────────────┘
                 │ k3s VMs use Ceph over the storage VLAN (ceph-csi, S3)
                 ▼
   k3s: 3 server VMs (one per host) + 2 agent VMs
```

| Hardware per node | |
| --- | --- |
| CPU | Intel i5-6500T, 4 cores |
| RAM | 16 GiB |
| NVMe | 256 GB: EFI + ext4 root (unchanged, no repartitioning) |
| HDD | 1 TB HGST, initialized as an LVM/BlueStore Ceph OSD |

Rough RAM budget per node: ~3–4 GB Ceph, ~1 GB host, ~11 GB for VMs.

## Repositories

| Repo | Owns | Tooling |
| --- | --- | --- |
| `nix-hgd1-cluster` (this repo) | Hosts, networking, Ceph, VM inventory, the k3s node OS, later the backend | Nix flake, `nixos-rebuild` |
| Workloads repo (later) | Everything running *on* k3s: ceph-csi, ingress, cert-manager, CloudNativePG, monitoring, apps (Cloudreve, …) | Kubernetes API (Helm/Terraform from `k3s-infra`, or Flux/Argo CD) |

The workloads repo only needs a kubeconfig; it does not depend on this flake.
`k3s-infra` is the source to port k3s modules (into this repo) and platform
add-ons (into the workloads repo) from.

## Key decisions

- **Hypervisor: microvm.nix.** VMs are NixOS configs in this flake and run as
  systemd units on the hosts. No live migration; k3s provides HA across hosts.
- **VMs are created only in Nix.** The future backend monitors and performs small
  actions (restart, drain/uncordon, host maintenance) but never defines VMs.
- **Ceph runs on the hosts, HDDs only.** One mon, mgr and OSD per host, replica 3.
  About 1 TB raw per node gives ~800 GB usable before nearfull.
- **Databases run on local NVMe and replicate themselves** (CloudNativePG), with
  continuous backups to Ceph S3. No NVMe partition for Ceph.
- **Static IPs for hosts** (Ceph monitor addresses must not change): infra
  `10.10.20.11–13`, storage `10.10.30.11–13`. VMs get static addresses on
  VLANs 30/40 from the inventory.

## Naming

`<site>-<role><nn>`: site `hgd1` (Hengelo Gld, site 1), a role code and a
two-digit number starting at 01. Roles: `hv` hypervisor (also runs Ceph),
`k8m` k3s server, `k8w` k3s agent; later e.g. `st` storage, `db`, `lb`, `bk`.
Hosts: `hgd1-hv01..03` (formerly `pve0..2`).

## Storage map

| Data | Where |
| --- | --- |
| Host OS, Nix store, VM disks, container images, etcd | Local NVMe |
| Postgres (Cloudreve DB and others) | CloudNativePG, 3 instances on local-path (one per host), backups to Ceph S3 |
| Redis / caches | Local NVMe or `emptyDir`, no backup |
| User files (Cloudreve) | Ceph S3 (RGW) on HDD |
| Logs, backups | Ceph S3 or RBD on HDD |
| Shared filesystem between pods | CephFS on HDD |
| Non-replicating app needing a disk | Ceph RBD (`ceph-bulk`) on HDD |

HDD-backed Ceph is slow (three laptop HDDs over 1 GbE): fine for files, logs and
backups, not for busy databases. If that becomes a problem, add SSDs later.

## Rules for workloads on k3s

1. Stateless apps can run anywhere.
2. Databases use a replicating operator (CloudNativePG): 3 instances on
   local-path, spread by `topology.kubernetes.io/zone` (= physical host),
   backups to Ceph S3. Write this as one reusable template.
3. Files and user data go to Ceph S3 (or CephFS when a shared filesystem is
   really needed), never local-path.
4. Apps needing a disk that do not replicate use Ceph RBD.
5. Caches may use local storage and are allowed to lose data.
6. Never put a single, non-replicated volume on local-path.

For every new app, ask: where does its state go? Usually Postgres (template),
S3, or nowhere.

---

## Step 0: Site network (OPNsense + Aruba)

**Repo:** `nix-hgd1-cluster` (`network/`) · **Status:** N0–N6 done; N5/N6
completed 2026-11-22 (83/83 probes and device reboot tests). N7 is in progress
(Cloudflare side done 2026-11-23, deploy pending) and is not a prerequisite for Ceph or the VM platform; see
[network/PLAN.md](network/PLAN.md) and the roadmap in [README.md](README.md)

OPNsense router and Aruba switch with VLANs: 10 mgmt, 20 infra (hypervisors),
30 storage (Ceph, not routed), 40 k8s, 100 wired users, in `10.10.0.0/16`.
`192.168.2.0/24` becomes only the internet uplink (OPNsense WAN).

Step 1 (host networking) is deployed as part of network plan N5; step 2
(Ceph) follows once N5–N6 are done.

**Current scope complete:** N0–N6 are done. N7 (remote access/hardening) is
in progress: deploy `cloudflared` to hv01–03, test, then close bootstrap WAN management.

## Step 1: Host networking

**Repo:** `nix-hgd1-cluster` (`inventory.nix`, `modules/network.nix`) · **Status:**
**deployed and verified 2026-11-22** during network plan N5; all three rebooted
with static INFRA/storage addresses. See [ROLLOUT.md](ROLLOUT.md).

- One NIC per host: untagged VLAN 20 for the host (`10.10.20.11–13`, gateway and
  DNS on OPNsense), `enp2s0.30` → bridge `br-stor` with the Ceph address
  (`10.10.30.11–13`), `enp2s0.40` → bridge `br-k8s` without a host address
  (for the k3s VMs in step 3).
- Time from OPNsense via chrony (public pool as fallback); internal domain
  `lan.buunk.org`.
- Rolled out one host at a time: `scripts/deploy.sh <host> boot`, switch the
  port to untagged 20 / tagged 30,40, reboot, verify.

**Done when:** all three hosts are reachable over SSH on `10.10.20.11–13` after
a reboot and reach each other on `10.10.30.0/24`.

## Step 2: Ceph on the hosts

**Repo:** `nix-hgd1-cluster` (`modules/ceph.nix`, `scripts/ceph-bootstrap.sh`) · **Status:** **done 2026-11-23**. HEALTH_OK, three monitors in quorum, three OSDs up/in and three RGWs. All pools use replica 3/min_size 2 with host-separated placement. RBD and S3 reads/writes passed through each single-host Ceph outage; hv02/hv03 reboot recovery and hv01 service recovery passed. Runtime-key backups are encrypted and decrypt-verified. See [CEPH.md](CEPH.md) and [ROLLOUT.md](ROLLOUT.md).

- Complete the extended SMART tests on all HDDs first. hv01 has historical
  unrecoverable-read errors; hv03 has a historical `Runtime_Bad_Block` count
  of 1. Current zero pending/reallocated counts are not sufficient qualification.
- Enable `services.ceph` on all hosts: mon + mgr on each, one OSD per HDD.
  Bootstrap (fsid, mon keyring, OSD creation with `ceph-volume`) is a one-time
  manual step; document the commands.
- Set `osd_memory_target` around 2 GB.
- Create pools: `k8s` (RBD for persistent volumes), RGW for S3. CephFS (MDS)
  only when needed.
- Create CephX users per consumer (k3s: only its pools); store keys with agenix.

**Done when:** `ceph -s` shows `HEALTH_OK`, 3 mons, 3 OSDs up/in, and a test
RBD image and S3 bucket work.

## Step 3: VM platform (microvm.nix)

**Repo:** `nix-hgd1-cluster` (`inventory.nix`, `modules/hypervisor.nix`, `modules/vm-guest.nix`) · **Status:** **done 2026-11-22**. Platform deployed on all hosts; `hgd1-k8m01` is live at `10.10.40.11` / `10.10.30.21`, with SSH, connectivity, persistent `/var/lib` and SSH identity verified across a VM restart. Host deployment preserved the running VM PID. See [VMS.md](VMS.md). hv02 needs BIOS virtualization enabled before it can run guests. Installing k3s/enabling the remaining four VMs is step 4.

- Add microvm.nix as a flake input.
- Add a `vms` section to `inventory.nix`: one entry per VM with `host`, `vcpu`,
  `memMB`, `diskGB`, `id` (used for MACs and tap names), `role` and its
  addresses on VLAN 40 and 30.
- Hypervisor module: on each host, run the VMs whose `host` matches, attach a
  tap to `br-k8s` (main NIC) and one to `br-stor` (Ceph), keep VM volumes under `/var/lib/microvms/<name>/`, set
  `restartIfChanged = false` so host deploys never restart all VMs at once.
- Bring up one empty test VM.

**Done when:** the test VM boots, gets its reserved IP, is reachable over SSH,
and its `/var/lib` volume survives a restart.

## Step 4: k3s nodes

**Repo:** `nix-hgd1-cluster` (`modules/k3s.nix`, ported from `k3s-infra`)

- 5 VMs: `hgd1-k8m01..03` (servers, one per host, embedded etcd, larger disk,
  e.g. `diskGB = 60` for local DB volumes) and agents `hgd1-k8w01..02`.
- `clusterInit` only for the very first bootstrap; afterwards all servers join
  through a fixed address (DNS name listing all servers, or a kube-vip VIP).
- k3s token: agenix secret encrypted to the laptop and the 3 hosts, shared
  read-only into the VMs over virtiofs (no re-keying when VMs are added).
- Label each node with its physical host: `topology.kubernetes.io/zone=<host>`.
- Pass Ceph mon IPs to the cluster for ceph-csi.
- Rolling update script: drain → restart VM → wait for Ready → uncordon, one
  VM at a time.
- Copy the kubeconfig to the laptop.

**Done when:** `kubectl get nodes` shows 5 Ready nodes with zone labels, and a
server VM can be restarted without losing quorum.

## Step 5: Document operations

**Repo:** `nix-hgd1-cluster` (`DEVELOPMENT.md`)

- Add a VM: inventory line, deploy the host.
- Move a VM: drain, `kubectl delete node`, change `host`, deploy the old host
  first and then the new host, delete the old volume directory.
- Restart and roll out VMs; host maintenance (`ceph osd set noout`, drain the
  host's VMs, reboot, unset `noout`).

**Done when:** each procedure has been executed once following the doc.

## Step 6: Platform add-ons on k3s

**Repo:** workloads repo (new)

- ceph-csi RBD (StorageClass `ceph-bulk`), CephFS when needed.
- local-path StorageClass for replicated databases only.
- Ingress and cert-manager (port from `k3s-infra`).
- S3 endpoint for RGW behind ingress with HTTPS.
- CloudNativePG operator plus the reusable Postgres template (3 instances,
  zone spread, backups to Ceph S3).

**Done when:** a test PVC binds on `ceph-bulk`, and a test Postgres cluster fails
over when one server VM is stopped.

## Step 7: Monitoring and logs

**Repo:** workloads repo

- Metrics and logs (e.g. VictoriaMetrics/VictoriaLogs from `k3s-infra`), stored
  on Ceph.
- Scrape host node_exporter and the Ceph mgr Prometheus endpoint.

**Done when:** host, Ceph, VM and pod health are visible in one place.

## Step 8: Apps (Cloudreve first)

**Repo:** workloads repo

- Cloudreve app: stateless deployment.
- Database: Postgres from the template.
- Files: S3 storage policy pointing at Ceph RGW with its own bucket and keys.
  Set a CORS rule for Cloudreve's domain; clients may need to reach RGW directly
  for presigned uploads/downloads. Check addressing style (path vs virtual host).
- Redis: cache, no persistence needed.

**Done when:** upload/download works through Cloudreve, files land in the Ceph
bucket, and the DB survives a server VM restart.

## Step 9: Backend (later)

**Repo:** `nix-hgd1-cluster` (package + `services.clusterd` NixOS module)

- Runs on the hosts as its own user; a polkit rule allows managing only
  `microvm@*.service`.
- Reads the VM list from the inventory (Nix decides what exists).
- Sources: systemd (VM state, cgroup CPU/RAM), Kubernetes API (nodes, drain),
  Ceph (`ceph status -f json` / mgr metrics), host metrics.
- Actions: restart/stop VM, drain + restart + uncordon, host maintenance mode.
- Clients: HTTP API, laptop CLI, web UI.

**Done when:** the UI shows host, VM, k3s and Ceph health and can restart a VM
safely.

---

## Open decisions

- Fixed k3s registration address: DNS round-robin or kube-vip VIP.
- Workloads repo tooling: port the Helm/Terraform approach from `k3s-infra`, or
  move to Flux/Argo CD.
- Fate of the Proxmox-based cluster (`k3s-infra`, `k3s-nixos-proxmox-prod`).
