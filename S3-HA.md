# Private S3 HA endpoint

## Live — 2026-11-23

**Application endpoint: `https://s3.lan.buunk.org`**

- Private VIP: `10.10.30.10:443`, on storage VLAN 30.
- HAProxy and Keepalived run directly on all three NixOS hypervisors.
- One host owns the VIP; its HAProxy can use any healthy RGW at
  `10.10.30.11–13:7480`. All RGWs share credentials, buckets and objects.
- No dependency on k3s, no extra VMs and no public storage exposure.
- Use region `us-east-1`, SigV4 and **path-style** addressing. Wildcard
  bucket hostnames are not configured.

```text
storage-connected application
        │ HTTPS (publicly trusted certificate)
        ▼
s3.lan.buunk.org → 10.10.30.10 (one VIP owner)
        │ HAProxy, health-checked backend selection
        ├── HTTP → hv01 RGW, 10.10.30.11:7480
        ├── HTTP → hv02 RGW, 10.10.30.12:7480
        └── HTTP → hv03 RGW, 10.10.30.13:7480
```

HTTPS terminates at HAProxy; backend HTTP stays on the private storage VLAN.
The original RGW endpoints remain available for diagnostics, but applications
should use the stable HTTPS endpoint. No Host/path/query rewrites are applied,
so S3 signatures and presigned URLs continue to work.

## Source of truth

| File | Owns |
| --- | --- |
| `inventory.nix` → `ceph.s3` | Hostname, VIP, VRRP ID, ACME email/server |
| `modules/s3-ha.nix` | HAProxy, Keepalived, TLS issuance/renewal, scoped firewall rules |
| `modules/ceph.nix` | Pins Ceph's advertised addresses to physical node IPs, never the VIP |
| `secrets/s3-acme-cloudflare.age` | Encrypted Cloudflare DNS credential |
| `secrets/secrets.nix` | Laptop and pinned hypervisor SSH-key recipients |

OPNsense Unbound has a host override for `s3.lan.buunk.org → 10.10.30.10`.
It is a DNS record only: storage still has no router interface/default gateway.
Record changes should follow the inventory; see [network/PLAN.md](network/PLAN.md).

## Certificates and credentials

Each host independently issues/renews a Let's Encrypt production certificate
using Cloudflare DNS-01. No public A record, inbound port or Cloudflare public
proxy is needed. These are **not Cloudflare Origin CA or self-signed production
certificates**. Public certificate transparency exposes the hostname, not S3.

- Certificate/account state: `/var/lib/acme/s3.lan.buunk.org` and
  `/var/lib/acme/.lego`, on local NVMe.
- The certificate group is `haproxy`; private keys have no world access.
- The API credential is root-only in `/run/agenix/s3-acme-cloudflare` and passed
  to the renewal unit through systemd credentials. No plaintext token is in Git
  or the Nix store.
- Existing Cloudflared login credentials had DNS read/write access but could
  not mint a separate token. The encrypted credential therefore reuses that
  existing token, **not a newly scoped DNS-only token**. Replace it with a
  buunk.org DNS-edit/zone-read-only token when available; do not revoke the
  existing credential without updating this secret.
- Daily jittered renewal checks run on every host. Certificate and proxy config
  changes reload HAProxy gracefully; no VM restart is involved.

TLS/account backups are encrypted and decrypt-verified outside Git at
`~/.local/state/nix-hgd1-cluster/s3-ha/hv*-acme-*.tar.gz.age`. These do not
back up S3 object data. Keep workload backups separately.

## Failover behavior

Keepalived uses unicast VRRP between the three physical storage addresses.
Only those peers, on `br-stor`, with TTL 255, may send accepted VRRP packets.
HTTPS is opened on the storage interface only. Standbys may bind the VIP before
owning it, but do not advertise it until eligible.

Eligibility checks a dedicated **loopback TLS listener** on `127.0.0.1:9443`.
It verifies the running proxy and its loaded publicly trusted certificate,
independently of RGW/Ceph health. A local RGW failure or expected Ceph
`HEALTH_WARN` must not withdraw a usable proxy VIP. Self-signed fallback/staging
certificates cannot make a node eligible.

Returning nodes do not automatically preempt a working owner. Existing TCP
connections cannot migrate between proxies: clients must retry interrupted
requests. Multipart state is shared, and retries can use another RGW. This
protects against host/service failures, not switch outages or every network
partition; VRRP is not a quorum/fencing protocol.

## Access and operate

Storage-connected VMs/applications can use the endpoint directly:

```sh
aws configure --profile homelab
aws configure set region us-east-1 --profile homelab
aws configure set s3.addressing_style path --profile homelab
aws --profile homelab --endpoint-url https://s3.lan.buunk.org s3 ls
```

Use application-specific S3 credentials; see [CEPH.md](CEPH.md). HAProxy does
not require S3 keys. Its logs omit object paths and presigned query strings.

Management uses WARP to the host INFRA addresses. The existing Gateway storage
block is preserved, so the laptop cannot connect directly to this VIP over
WARP. For a TLS-valid connectivity check through an authorized SSH forward:

```sh
ssh -N -L 127.0.0.1:17443:10.10.30.10:443 jurre@10.10.20.11
# In another terminal; hostname/SNI and certificate validation remain intact:
curl --noproxy '*' --connect-to s3.lan.buunk.org:443:127.0.0.1:17443 \
  https://s3.lan.buunk.org/
```

Do not use `https://127.0.0.1` with certificate verification disabled. AWS CLI
through such a forward needs a suitable local hostname mapping/proxy; the
example above does not alter laptop DNS or relax Gateway policy.

```sh
ssh jurre@10.10.20.11 'systemctl status haproxy keepalived --no-pager'
ssh jurre@10.10.20.11 'ip -br addr show br-stor; sudo ceph -s'
ssh jurre@10.10.20.11 'systemctl status acme-renew-s3.lan.buunk.org.timer'
```

Maintenance remains one host at a time, with Ceph `noout` where appropriate and
HEALTH_OK before touching another node. Keepalived/HAProxy are independent of
Ceph units; stopping either on the active owner can move the VIP.

## Verified acceptance

- Staging DNS-01 issuance succeeded, but staging trust did not advertise the VIP.
- All three nodes obtained trusted production certificates; renewal checks and
  timers passed. No extra certificates were forced during renewal tests.
- SigV4 PUT/GET, escaped/unicode object names, presigned URLs and 12 MiB multipart
  uploads worked through the HTTPS VIP with byte-for-byte verified results.
- Local Ceph/RGW outage left the healthy proxy's VIP in place; signed S3 I/O
  continued through the other hosts while Ceph was HEALTH_WARN.
- Stopping only the active HAProxy moved the VIP in approximately five seconds.
  An in-flight throttled 12 MiB PUT retried twice and completed byte-identically.
- Stopping Keepalived also transferred the VIP. Returning nodes did not preempt.
- The actual VIP-owner hv02 reboot transferred ownership; data remained intact,
  services returned automatically and Ceph recovered HEALTH_OK.
- Final state: exactly one VIP owner, three healthy backends on every proxy,
  no failed host units/no lingering `noout`, and the live VM PID unchanged.
- Temporary verification bucket/objects removed. Combined HAProxy/Keepalived
  memory was approximately **20–31 MiB per host** after these tests; load varies.

Detailed private evidence/backups are under
`~/.local/state/nix-hgd1-cluster/s3-ha/`, outside Git.
