---
icon: lucide/database
---

# Ceph

Ceph turns the three HDDs into one storage cluster that survives losing a
host. It runs directly on the hypervisors, so storage doesn't depend on the
VMs or Kubernetes that use it.

!!! info "At a glance"

    **Status** <span class="status">Done</span>, HEALTH_OK · **Version** Ceph
    20.2.4 (Tentacle) · **Configured in** `modules/ceph.nix`,
    `inventory.nix` → `ceph`, `hosts.*.osd` · **Created with**
    `ceph-bootstrap`

## Overview

Every host runs the same four daemons, all on the storage VLAN (`br-stor`):

| Daemon | Role |
| --- | --- |
| Monitor `ceph-mon-hgd1-hvNN` | Cluster map and quorum; needs 2 of 3 |
| Manager `ceph-mgr-hgd1-hvNN` | One active, two standby; Prometheus metrics on 9283 |
| OSD `ceph-osd-N` | Stores data on that host's HDD; memory target 2 GiB |
| RGW `ceph-rgw-rgw.hgd1-hvNN` | S3 gateway on `<storage-ip>:7480` |

## How it works

### Placement

- Every pool has `size = 3`, `min_size = 2`, and the CRUSH rule puts each copy
  on a different **host**.
- One host down: everything still reads and writes on two copies, and Ceph
  catches the host up when it returns.
- Two hosts down: writes stop.
- Three 1 TB HDDs at three copies give about 800 GB before Ceph warns it's
  nearly full.

| Pool | Use |
| --- | --- |
| `k8s` | Meant for RBD volumes of Kubernetes; unused, since pods keep state in Postgres or S3 (no ceph-csi) |
| RGW pools (`.rgw.root`, `default.rgw.*`) | S3, created by the gateways |
| `.mgr` | Manager state |

### Access

Only machines on the storage VLAN reach Ceph: the hosts and the VMs' storage
NICs. The firewall opens Ceph ports on `br-stor` only (3300 and 6789 for
monitors, 6800–7300 for OSDs, 7480 for RGW, 9283 for metrics). Storage isn't
routed and Cloudflare Gateway blocks it, so the laptop can't reach Ceph
directly.

Kubernetes gets the cluster facts from the ConfigMap `kube-system/hgd1-ceph`.
The VMs run Linux 7.x, which Ceph 20's kernel clients need; mapping an RBD
image from a VM has been tested.

### Keys

Admin and daemon keyrings exist only on the hosts (mode 0600), never in Git
or the Nix store. Encrypted, decrypt-tested backups are on my laptop under
`~/.local/state/nix-hgd1-cluster/ceph-bootstrap/`. They restore the cluster's
identity, not its data.

## Configuration

| What | Where |
| --- | --- |
| FSID, monitors, pool defaults, daemons, firewall | `modules/ceph.nix` |
| FSID | `inventory.nix` → `ceph.fsid` |
| HDD path, OSD id and UUID | `inventory.nix` → `hosts.<name>.hdd`, `.osd` |

Daemons only start once their keyring exists, so the module can be deployed
before the cluster is created. `public addr` is pinned to the host's storage
IP, so Ceph never advertises the S3 VIP.

### Creating a cluster

`ceph-bootstrap` created this cluster. Use it only for a brand new
one, never to replace a disk.

```sh
ceph-bootstrap check  # read-only: identity, FSID, reachability, clock offset
ceph-bootstrap        # all phases; asks you to type "wipe" before touching disks
```

| Phase | What it does |
| --- | --- |
| `mon` | Keyrings and a monmap with all three monitors; waits for quorum |
| `mgr` | One manager per host |
| `osd` | Checks each HDD (serial, not mounted, blank, SMART healthy, extended test within 24 power-on hours), asks for `wipe`, creates the OSD |
| `pools` | The `k8s` RBD pool and the Prometheus module |
| `rgw` | One S3 gateway per host |

Every phase skips work that already exists, so rerunning is safe.

## Operating

```sh
labctl ceph status                         # health, every check, OSDs up/in, PGs, raw capacity
labctl disk list                           # each OSD's drive: size, how full, SMART
labctl s3 status                           # the object store on top: room left
labctl logs --since 1h 'unit:"ceph-osd"*'  # what the OSDs said
```

??? note "On a host: the full Ceph CLI"

    For anything beyond status, and for changes (flags, OSDs), SSH in:

    ```sh
    ssh jurre@10.10.20.11
    sudo ceph health detail      # why it is not OK
    sudo ceph osd tree           # OSDs per host
    sudo ceph osd df tree        # usage per OSD and host
    sudo ceph df                 # usage per pool
    ```

- Host work: set `noout` first, see [Host maintenance](../operate/host-maintenance.md).
- Failed disk: [Disk replacement](../operate/disk-replacement.md).
- Disk risks: [Hosts → Disk health](hosts.md#disk-health).

## Troubleshooting

See [Troubleshooting → Ceph](../operate/troubleshooting.md#ceph-not-healthy)
for what each warning means.

## Tested

- RBD write and read-back of 16 MiB, byte for byte.
- S3 through every gateway, 12 MiB multipart across gateways, SHA-256-checked
  reads.
- Each host's Ceph services stopped in turn while I/O continued; manager
  failover worked.
- hv02 and hv03 really rebooted; their OSDs came back on their own.

## Related

- [S3 endpoint](s3.md) · [Build an app](https://jurrebuunk.github.io/hgd1-k8s/how-to/build-an-app/)
