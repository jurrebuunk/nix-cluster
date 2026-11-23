# Ceph storage operations

## Current status — 2026-11-23

**PLAN step 2 is complete.** Ceph 20.2.4 is initialized and HEALTH_OK:

- Three monitors in quorum, one active manager and two standbys.
- Three HDD-backed BlueStore OSDs up/in, one per physical host.
- CRUSH `replicated_rule` uses host failure domains; all nine current pools
  have `size=3`, `min_size=2`. `k8s` is initialized for RBD.
- Three RGWs bound to their storage IPs on port 7480, sharing one object store.
- The `jurre` S3 user exists; its credentials are root-only on hv01 at
  `/root/jurre-s3-credentials.json`, not in Git or the Nix store.
- Temporary RBD images/bucket and the temporary RBD client were removed after
  acceptance tests. No application buckets or k3s workloads are provisioned yet.

All three HDDs passed recent extended SMART tests before initialization, with
IDs 5/196/197/198 zero. The owner accepted the current disks for this homelab;
passing qualification does not erase historical risks:

| Host | HDD serial / OSD | Qualification and remaining caution |
| --- | --- | --- |
| hgd1-hv01 | JR1004BNK14S5M / osd.0 | Extended test passed. Historical UNC errors and saturated ATA count 65535 remain; last logged error at power-on hour 6858 versus 14214 at qualification. Not a current bad-sector count. |
| hgd1-hv02 | JR1000D30JXXWF / osd.1 | Extended test passed; no ATA errors or critical-sector indicators at qualification. |
| hgd1-hv03 | JR1000D30JXYRF / osd.2 | Extended test passed; historical `Runtime_Bad_Block = 1` remains. |

Monitor SMART and Ceph health; replace failed media promptly. Ceph can tolerate
one host/OSD outage with two replicas available, but cannot restore the third
host-separated copy until replacement capacity returns. A second failure can
stop I/O. Keep independent backups; none of these tests guarantees future disk
reliability. These findings refer to the HDDs, not the NVMe OS disks.

## Acceptance and recovery tests

Verified on the live cluster:

- A pool-scoped RBD client imported/exported 16 MiB with byte-for-byte equality.
- S3 bucket creation, writes through every frontend, a 12 MiB multipart upload
  across frontends, and SHA256-verified reads through all three endpoints.
- Each host's mon/mgr/OSD/RGW services stopped in turn: the remaining two hosts
  continued serving new RBD and S3 writes and reads. Manager failover worked.
- hv02 and hv03 then actually rebooted, one at a time. Their OSD LVM devices,
  keyrings and services returned automatically; persisted data remained intact.
- hv01 used a service stop/start test, **not a physical reboot**, to preserve
  its running VM. The VM remained running throughout the Ceph rollout.
- After every recovery, three monitors/OSDs returned and all PGs were clean;
  maintenance `noout` was removed. Bootstrap rerun also passed without reformatting
  existing OSDs or rotating keys.

Encrypted, decrypt-verified runtime-key/configuration backups are stored outside
Git under `~/.local/state/nix-hgd1-cluster/ceph-bootstrap/*-runtime-*.tar.gz.age`.
Recipients are the laptop admin SSH key and the three pinned host SSH keys.
Use the newest verified archive and keep restored keyrings mode 0600.
These protect recovery material, **not application objects or RBD contents**;
independent workload backups remain separate work.

## Qualification and bootstrap (fresh-cluster procedure)

Authoritative serials, whole-disk by-id paths, OSD IDs/UUIDs and cluster FSID
live in `inventory.nix`. The NVMe disks must never be handed to Ceph.

From the laptop repo, with WARP connected:

```sh
scripts/ceph-bootstrap.sh check
ssh jurre@10.10.20.11 'sudo smartctl -a /dev/sda'
# Inspect all three hosts, not just hv01.
```

The `check` phase is read-only: it verifies SSH identity, hostname, Ceph FSID,
storage reachability and clock offset. It does not qualify media or initialize
anything. The OSD phase additionally requires:

- A whole block device with the inventory serial, not root or mounted media.
- Blank disk signatures for a new OSD; existing OSDs must match inventory identity.
- Successful current SMART health, with IDs 5/196/197/198 all zero.
- The latest test is extended, successfully completed, and within 24 power-on hours.
- An explicit `wipe` confirmation before destructive LVM/BlueStore initialization.

For a fresh cluster, only after all hosts qualify:

```sh
scripts/ceph-bootstrap.sh     # mon, mgr, osd, pools, rgw; asks for wipe
```

Remote commands fail fast with `umask 077`; all runtime keyrings are mode 0600,
including existing mgr/RGW keys on rerun. Admin/daemon keyrings are runtime
state, never plaintext in this repository or the Nix store. See [ROLLOUT.md](ROLLOUT.md)
part E for phases and post-bootstrap verification. Replication is not a backup.

## Live S3 endpoints

Each host runs one RGW frontend for the **same** Ceph object store:

| Endpoint | Host |
| --- | --- |
| `http://10.10.30.11:7480` | hgd1-hv01 |
| `http://10.10.30.12:7480` | hgd1-hv02 |
| `http://10.10.30.13:7480` | hgd1-hv03 |

Credentials and buckets are shared across frontends. These are private HTTP
endpoints on the unrouted storage VLAN; there is currently no S3 VIP, friendly
S3 DNS alias, TLS ingress or public exposure. Three frontends alone do not give
a client automatic failover. Workloads with a storage NIC can use them directly;
a future authenticated/TLS ingress is separate work.

From the laptop, tunnel through a hypervisor with WARP connected (the router
cannot route storage, and Gateway blocks `10.10.30.0/24` over WARP):

```sh
ssh -N -L 17480:10.10.30.11:7480 jurre@10.10.20.11
```

Use `http://127.0.0.1:17480` as the endpoint on that laptop while the tunnel
runs. The SSH tunnel encrypts the laptop-to-host connection; direct storage
HTTP is not TLS.

## Creating an S3 user and bucket

RGW is running and `jurre` already exists. Retrieve its existing root-only
credentials securely from hv01; do not rotate them just to configure a client.
For a **new, separate** S3 user, follow the procedure below with a distinct UID.
An S3 user's access/secret keys differ from CephX/RBD client keys or an SSH login.

On a Ceph host, create a user once, storing its returned credentials privately:

```sh
sudo sh -c 'umask 077; radosgw-admin user create --uid=my-app \
  --display-name="My application" > /root/my-app-s3-credentials.json'
```

Retrieve the access/secret key securely for your client. Do not paste the JSON
into chat/logs or commit it. On the client, configure an AWS CLI profile:

```sh
aws configure --profile homelab
# Enter the S3 user's keys; default region us-east-1.
aws --profile homelab --endpoint-url http://127.0.0.1:17480 \
  s3 mb s3://my-bucket
aws --profile homelab --endpoint-url http://127.0.0.1:17480 s3 ls
```

Inside the storage network, substitute one of the direct RGW endpoints.
Bucket names are shared across this object store, not separate per frontend.
Create separate users/credentials for applications rather than sharing a
personal user's keys or the cluster's administrator keyring.
