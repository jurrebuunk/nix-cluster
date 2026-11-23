# Ceph

Ceph turns the three HDDs into one storage cluster that survives losing a
host. It runs directly on the hypervisors, so storage doesn't depend on the
VMs or Kubernetes that use it.

## What runs where

Every host runs the same four daemons, all on the storage VLAN (`br-stor`):

| Daemon | Per host | Role |
| --- | --- | --- |
| Monitor (`ceph-mon-hgd1-hvNN`) | 1 | Cluster map and quorum; needs 2 of 3 |
| Manager (`ceph-mgr-hgd1-hvNN`) | 1 | One active, two standby; Prometheus metrics on port 9283 |
| OSD (`ceph-osd-N`) | 1 | Stores data on that host's HDD (BlueStore on LVM), memory target 2 GiB |
| RGW (`ceph-rgw-rgw.hgd1-hvNN`) | 1 | S3 gateway on `<storage-ip>:7480` |

Ceph 20.2.4 (Tentacle). The FSID and monitor addresses come from
`inventory.nix`; the daemons are configured in `modules/ceph.nix` and only
start once their keyring exists.

## How data is placed

- Every pool uses `size = 3` and `min_size = 2`, and the CRUSH rule puts
  each copy on a different **host**.
- One host can be down and everything still reads and writes on two copies.
  When it returns, Ceph catches it up.
- With **two** hosts down, writes stop: fewer than `min_size` copies are left.
- Three 1 TB HDDs at three copies leave about 800 GB usable before Ceph warns
  that it is nearly full.

| Pool | Use |
| --- | --- |
| `k8s` | RBD block devices for Kubernetes (ceph-csi, step 6) |
| `.rgw.*` / `default.rgw.*` | Created by RGW for S3 |
| `.mgr` | Manager state |

## Daily commands

On any host:

```sh
sudo ceph -s                 # overall health
sudo ceph health detail      # why it is not OK
sudo ceph osd tree           # OSDs per host, up/in
sudo ceph osd df tree        # usage per OSD and host
sudo ceph df                 # usage per pool
```

`HEALTH_OK` is the normal state. `HEALTH_WARN` with a reason like
`noout flag(s) set` is expected during maintenance.

## Who can reach Ceph

Only machines on the storage VLAN: the three hosts and the VMs' storage NICs.
The host firewall opens the Ceph ports on `br-stor` only (3300 and 6789 for
monitors, 6800–7300 for OSDs, 7480 for RGW, 9283 for metrics). Storage is not
routed, and Cloudflare Gateway blocks it too, so the laptop can't reach Ceph
directly, even over WARP. Use an SSH forward when you need to (see
[S3](s3.md#from-the-laptop)).

Kubernetes nodes get the cluster facts from the ConfigMap
`kube-system/hgd1-ceph` (FSID, monitors, S3 endpoint). The VMs run Linux 7.x,
which Ceph 20's kernel clients need for their authentication cipher; mapping
an RBD image from a VM has been tested.

## Disk health and risk

All three HDDs passed an extended SMART test just before Ceph initialised
them. Their history is in [Hosts](../hosts/index.md#disk-health). In short:
these are used laptop disks I've accepted for a homelab.

- Check SMART now and then:
  `sudo smartctl -a /dev/disk/by-id/ata-HGST_*` (skip the `-part` entries).
- A failed disk costs no data while the other two copies are healthy, but the
  third copy can only come back once there is a replacement disk.
- **Replication is not a backup.** Deleting a bucket deletes it three times.

## Recovery material

The Ceph admin and daemon keyrings live only on the hosts (mode 0600), never
in Git or the Nix store. Encrypted backups of them are on my laptop under
`~/.local/state/nix-hgd1-cluster/ceph-bootstrap/*-runtime-*.tar.gz.age`,
encrypted to my key and the three host keys, and decrypt-tested. They let you
rebuild the cluster's identity, not its data.

## Bootstrapping a new cluster

`scripts/ceph-bootstrap.sh` created this cluster. Use it only for a brand new
cluster, never to replace a disk.

```sh
scripts/ceph-bootstrap.sh check    # read-only: identity, FSID, storage reachability, clock offset
scripts/ceph-bootstrap.sh          # all phases; asks you to type "wipe" before touching disks
```

| Phase | What it does |
| --- | --- |
| `mon` | Creates mon and admin keyrings and a monmap with all three monitors; starts them and waits for quorum |
| `mgr` | One manager per host |
| `osd` | Checks each HDD (serial, not mounted, blank, SMART healthy, extended test passed within 24 power-on hours), asks for `wipe`, creates a BlueStore OSD on LVM |
| `pools` | Creates the `k8s` RBD pool and enables the manager's Prometheus module |
| `rgw` | One S3 gateway per host |

Every phase skips work that already exists, so rerunning after a failure is
safe. Before running it on new disks, check SMART first: any reallocated or
pending sectors, or a failed extended test, keeps that disk out.

## What was tested

- An RBD client wrote and read back 16 MiB byte for byte.
- S3 writes through every gateway, a 12 MiB multipart upload spread over
  gateways, and SHA-256-checked reads through all three.
- Each host's Ceph services were stopped in turn; the other two kept serving
  RBD and S3, and the manager failed over.
- hv02 and hv03 were really rebooted; their OSDs came back by themselves.
- After every test all placement groups returned to clean.
