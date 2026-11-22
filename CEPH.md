# Ceph storage operations

## Current status — 2026-11-22

N5/N6 are complete. Ceph packages/configuration are deployed on all three
hosts, but daemon startup is gated by keyrings. **The cluster is not initialized:
there are no running RGW endpoints, OSDs, pools or buckets yet.** Extended SMART
tests are running; their initial completion estimates are 22:58–23:15 CET.
Do not reboot the hosts or initialize the HDDs before qualification completes.
VM platform work uses NVMe and does not depend on these tests.

| Host | Reserved HDD serial | Findings before the extended test |
| --- | --- | --- |
| hgd1-hv01 | JR1004BNK14S5M | Historical UNC read errors; ATA counter saturated at 65535, last logged at power-on hour 6858 versus about 14212 now. This is not a count of current bad sectors. Treat as suspect, especially for important data. |
| hgd1-hv02 | JR1000D30JXXWF | No ATA errors logged; no current critical-sector indicators. Full test still required. |
| hgd1-hv03 | JR1000D30JXYRF | Historical `Runtime_Bad_Block = 1`; no ATA errors logged. Full test still required. |

All three currently report zero reallocated sectors, reallocation events,
pending sectors and offline-uncorrectable sectors. Those zero counters and an
overall SMART "PASSED" do not override the history or substitute for a surface
test. Consider replacing hv01's HDD before storing important data even if the
extended test passes. These findings refer to the HGST HDDs, not the NVMe OS disks.

## Qualification and bootstrap

Authoritative serials, whole-disk by-id paths, OSD IDs/UUIDs and cluster FSID
live in `inventory.nix`. The NVMe disks must never be handed to Ceph.

From the laptop repo, before N7:

```sh
export JUMP=root@192.168.2.12
scripts/ceph-bootstrap.sh check
ssh -J "$JUMP" jurre@10.10.20.11 'sudo smartctl -a /dev/sda'
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

Only after all hosts qualify:

```sh
scripts/ceph-bootstrap.sh     # mon, mgr, osd, pools, rgw; asks for wipe
```

Remote commands fail fast. Admin/daemon keyrings are runtime state, never
plaintext in this repository or the Nix store. See [ROLLOUT.md](ROLLOUT.md)
part E for phases and post-bootstrap verification. Replication is not a backup.

## S3 endpoints (after successful bootstrap)

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

From home Wi-Fi, tunnel through a hypervisor (the router cannot route storage):

```sh
ssh -N -J root@192.168.2.12 \
  -L 17480:10.10.30.11:7480 jurre@10.10.20.11
```

Use `http://127.0.0.1:17480` as the endpoint on that laptop while the tunnel
runs. The SSH tunnel encrypts the laptop-to-host connection; direct storage
HTTP is not TLS.

## Creating an S3 user and bucket

These commands apply **after RGW is running**. An S3 user's access/secret keys
are different from CephX/RBD client keys or an SSH login.

On a Ceph host, create a user once, storing its returned credentials privately:

```sh
sudo sh -c 'umask 077; radosgw-admin user create --uid=jurre \
  --display-name="Jurre" > /root/jurre-s3-credentials.json'
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
