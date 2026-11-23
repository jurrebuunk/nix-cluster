# Roadmap and history

The project was built in numbered steps. Network steps start with **N**,
cluster steps are plain numbers. Each step had a "done when" check, and a step
was only marked done after that check passed on the live system.

## Status

| Step | What | Status |
| --- | --- | --- |
| N0 | Bootstrap: cabling, OPNsense install, SSH access | Done 2026-11-21 |
| N1 | OPNsense base: firmware, DNS with DNSSEC, NTP, backups | Done 2026-11-21 |
| N2 | VLAN interfaces 20/40/100, DHCP on MGMT and USERS, outbound NAT | Done 2026-11-21 |
| N3 | Switch: VLANs, port roles, management on `10.10.10.2`, key-based SSH | Done 2026-11-21 |
| N4 | Firewall policy between VLANs | Done 2026-11-21 |
| N5 / 1 | Hosts on their static VLAN 20/30/40 addresses | Done 2026-11-22 |
| N6 | Verify the network | Done 2026-11-22 |
| N7 | Remote access through Cloudflare; WAN management closed | Done 2026-11-23 |
| 2 | Ceph on the hosts | Done 2026-11-23 |
| 2.1 | Highly available S3 endpoint with trusted HTTPS | Done 2026-11-23 |
| 3 | VM platform (microvm.nix) | Done 2026-11-22 |
| 4 | k3s nodes: 3 servers, 2 agents | **Partly done**: 4 of 5 nodes; `hgd1-k8m02` waits for VT-x on hv02 |
| 5 | Operations docs, each procedure run once | Partly done: these docs |
| 6 | Platform add-ons on k3s (workloads repo) | Planned |
| 7 | Monitoring and logs | Planned |
| 8 | Apps, Cloudreve first | Planned |
| 9 | My own backend for monitoring and small actions | Later |

Outside the repo, still to do:

- [ ] Enable VT-x in hv02's BIOS, then finish step 4
      ([how](../compute/k3s.md#finishing-the-cluster)).
- [ ] Reserve WAN address `192.168.2.12` on the home router for OPNsense's
      onboard MAC `90:1b:0e:fa:70:dd`.
- [ ] Update the Aruba firmware (still `YA.16.02.0012`).

## What each finished step proved

**Network (N0–N7).** 83 of 83 probes passed from throwaway clients on every
VLAN: DHCP, DNS, NTP, NAT, inter-VLAN policy, host SSH isolation, load
balancer boundaries, and storage reachable on layer 2 with no router
interface. OPNsense and the switch were rebooted; everything came back from
saved config. Remote access worked with one hypervisor's connector stopped.
See [Network](../network/index.md).

**Hosts on static addresses (N5).** Each host was identified by MAC and SSH
host key, moved one at a time with a self-reverting guard armed, rebooted and
verified before the next one.

**Ceph (2).** All three HDDs passed an extended SMART test first. RBD and S3
reads and writes kept working with each host's Ceph services stopped in turn;
hv02 and hv03 also survived real reboots. Every placement group returned to
clean. See [Ceph](../storage/ceph.md).

**S3 endpoint (2.1).** Signed requests, multipart and presigned uploads worked
through the HTTPS VIP. Stopping the active proxy moved the VIP in about five
seconds, and an interrupted 12 MiB upload completed after a retry. See
[S3](../storage/s3.md).

**VM platform (3).** A test VM kept its data and SSH identity across restarts,
and a host deploy did not restart it. A VM could not reach host management
through either guest bridge.

**k3s (4, so far).** Pods on all four nodes reach each other, cluster DNS, the
internet, the Ceph monitors and the S3 endpoint. `kubectl` works from the
laptop over WARP. A rolling restart of an agent worked, and a VM mapped and
wrote a real Ceph RBD image with the kernel client. See
[k3s](../compute/k3s.md).

## Planned work

**Step 5: operations.** Each procedure in [Operations](../operations/index.md)
gets run once by following the docs: add a VM, move a VM, roll out VMs, and
host maintenance.

**Step 6: platform add-ons** (workloads repo).

- ceph-csi RBD with a `ceph-bulk` StorageClass; CephFS only when needed.
- `local-path` only for databases that replicate themselves.
- Ingress and cert-manager, with load balancer IPs on VLAN 40 `.200–.249`.
- CloudNativePG plus one reusable Postgres template: three instances, spread
  over zones, backups to Ceph S3.
- Done when a test PVC binds on `ceph-bulk` and a test Postgres cluster
  fails over when a server VM stops.

**Step 7: monitoring and logs.** VictoriaMetrics and VictoriaLogs (ported from
my old `k3s-infra` repo), stored on Ceph, scraping host `node_exporter` and the
Ceph manager's Prometheus endpoint. Done when host, Ceph, VM and pod health
are visible in one place.

**Step 8: apps.** Cloudreve first: stateless deployment, Postgres from the
template, files in its own S3 bucket, Redis as a cache. Done when uploads land
in Ceph and the database survives a server VM restart.

**Step 9: my own backend.** A small service on the hosts (`services.clusterd`)
that reads the VM list from the inventory and combines systemd, Kubernetes and
Ceph status. It can restart a VM, drain and uncordon nodes and put a host in
maintenance, from a web UI or a laptop CLI. It never defines VMs; Nix does.

## Open decisions

- Workloads repo tooling: port the Helm/Terraform approach from `k3s-infra`,
  or move to Flux or Argo CD.
- What happens to the old Proxmox-era repos (`k3s-infra`,
  `k3s-nixos-proxmox-prod`).
- Network extras: Wi-Fi access point, guest and IoT VLANs, a DMZ, LACP over the
  spare router ports, jumbo frames on the storage VLAN.
