---
icon: lucide/map
---

# Roadmap

The project was built in numbered steps. Network steps start with **N**,
cluster steps are plain numbers. Each step had a "done when" check, and a step
was only marked done after that check passed on the live system.

## Status

| Step | What | Status |
| --- | --- | --- |
| N0 | Bootstrap: cabling, OPNsense install, SSH access | <span class="status">Done</span> 2026-11-21 |
| N1 | OPNsense base: firmware, DNS with DNSSEC, NTP, backups | <span class="status">Done</span> 2026-11-21 |
| N2 | VLAN interfaces 20/40/100, DHCP on MGMT and USERS, outbound NAT | <span class="status">Done</span> 2026-11-21 |
| N3 | Switch: VLANs, port roles, management on `10.10.10.2`, key-based SSH | <span class="status">Done</span> 2026-11-21 |
| N4 | Firewall policy between VLANs | <span class="status">Done</span> 2026-11-21 |
| N5 / 1 | Hosts on their static VLAN 20/30/40 addresses | <span class="status">Done</span> 2026-11-22 |
| N6 | Verify the network | <span class="status">Done</span> 2026-11-22 |
| N7 | Remote access through Cloudflare; WAN management closed | <span class="status">Done</span> 2026-11-23 |
| 2 | Ceph on the hosts | <span class="status">Done</span> 2026-11-23 |
| 2.1 | Highly available S3 endpoint with trusted HTTPS | <span class="status">Done</span> 2026-11-23 |
| 3 | VM platform (microvm.nix) | <span class="status">Done</span> 2026-11-22 |
| 4 | k3s nodes: 3 servers, 2 agents | <span class="status">Done</span> 2026-11-23 |
| 5 | Operations docs, each procedure run once | <span class="status status--partial">Partial</span> these docs |
| 7 | Monitoring and logs for the infrastructure | <span class="status">Done</span> 2026-11-23 |
| 9 | Platform API, CLI and web UI | <span class="status status--partial">API v1.1.0 live</span> |

Outside the repo, still to do:

- [ ] Reserve WAN address `192.168.2.12` on the home router for OPNsense's
      onboard MAC `90:1b:0e:fa:70:dd`.
- [ ] Update the Aruba firmware (still `YA.16.02.0012`).

## Proven

**Network (N0–N7).** 83 of 83 probes passed from throwaway clients on every
VLAN: DHCP, DNS, NTP, NAT, inter-VLAN policy, host SSH isolation, load
balancer boundaries, and storage reachable on layer 2 with no router
interface. OPNsense and the switch were rebooted; everything came back from
saved config. Remote access worked with one hypervisor's connector stopped.
See [Network](../concepts/network.md).

**Hosts on static addresses (N5).** Each host was identified by MAC and SSH
host key, moved one at a time with a self-reverting guard armed, rebooted and
verified before the next one.

**Ceph (2).** All three HDDs passed an extended SMART test first. RBD and S3
reads and writes kept working with each host's Ceph services stopped in turn;
hv02 and hv03 also survived real reboots. Every placement group returned to
clean. See [Ceph](../concepts/ceph.md).

**S3 endpoint (2.1).** Signed requests, multipart and presigned uploads worked
through the HTTPS VIP. Stopping the active proxy moved the VIP in about five
seconds, and an interrupted 12 MiB upload completed after a retry. See
[S3](../concepts/s3.md).

**VM platform (3).** A test VM kept its data and SSH identity across restarts,
and a host deploy did not restart it. A VM could not reach host management
through either guest bridge.

**k3s (4).** Five Ready nodes with zone labels and three etcd members. Pods on
every node reach each other, cluster DNS, the internet, the Ceph monitors and
the S3 endpoint. `kubectl` works over WARP. Restarting the server that held
the API VIP kept the API up (41 of 41 checks), and a VM mapped and wrote a real
Ceph RBD image. See [k3s](../concepts/k3s.md).

**Monitoring (7).** All 77 scrape targets up across three hosts, identical
copies on every host (also after a store was down), logs from all hosts, VMs,
router and switch, and the query VIP moved when its store stopped. See
[Monitoring](../concepts/monitoring.md).

## Planned

**Step 5: operations.** Each procedure in [Operate](../operate/index.md)
gets run once by following the docs: add a VM, move a VM, roll out VMs, and
host maintenance.

**Step 9: Platform API, CLI and web UI.** `clusterd`, a REST API on all three
hosts behind `https://api.lan.buunk.org`, with token auth and a read-only
proxy for metrics and logs, and the `labctl` CLI (both in the
[`clusterd`](https://github.com/jurrebuunk/clusterd) repo); and
[`lab-console`](https://github.com/jurrebuunk/lab-console), the web UI at
`lab.buunk.org` on k3s. What the API can do grows one action at a
time; it never defines VMs, Nix does. **Done:** `clusterd` `v1.1.0` runs on all hosts: status per part
(including disks and S3), metrics, logs, `labctl health`, and VM
restart/stop/start/roll, node cordon and host maintenance through `labctl`.
**Next:** the web UI. See [Platform API](../concepts/api.md),
[Use the CLI](../how-to/use-the-cli.md) and [Web UI](../concepts/web-ui.md).

## Future

- **Alerting:** vmalert and a clustered Alertmanager with rules for hosts,
  Ceph and SMART.
- **Heartbeat:** an always-firing alert to an external service, so silent
  monitoring gets noticed.
- **Secrets manager (KMS)** for workloads; see [Credentials](credentials.md#future-a-kms).
- **Single sign-on** for the API, CLI and web UI instead of tokens.

## Other repos

Cluster components (Flux, public access, Postgres, Keycloak) live in `hgd1-k8s`, the
router and switch move to Ansible in `hgd1-network`. Each has a `PLAN.md`
with its next steps; see [Repositories](repositories.md).

## Open issues

Problems found and worked around, with the real fix still to do. Each has a
GitHub issue in the repo that owns the fix.

| Issue | Workaround now | Real fix | Where |
| --- | --- | --- | --- |
| OPNsense's Unbound answers "no address" (NOERROR) instead of "no such name" (NXDOMAIN) for names under `lan.buunk.org` that don't exist (found 2026-11-24) | k3s pods use their own resolver file without `search lan.buunk.org` ([k3s](../concepts/k3s.md)) | Make Unbound answer NXDOMAIN for unknown names in the zone (local-zone type) | [hgd1-network#1](https://github.com/jurrebuunk/hgd1-network/issues/1) (private repo) |
| Host maintenance with a reboot has never run on a real host | The manual steps on [Host maintenance](../operate/host-maintenance.md) | One real `labctl host maintenance <host> --reboot` and `resume` | [#2](https://github.com/jurrebuunk/nix-hgd1-cluster/issues/2) |
| Tunnel hostnames get their DNS record by hand (`test.buunk.org` through the Cloudflare API) | One record per app, made by hand | external-dns in the cluster, records in Git next to the routes | [hgd1-k8s#1](https://github.com/jurrebuunk/hgd1-k8s/issues/1) |
| Old public names (`drive`, `crm`, `matrix`, …) point at tunnels from the Proxmox era that are down | – | Move what should live on to `hgd1-apps`, delete the rest | [#3](https://github.com/jurrebuunk/nix-hgd1-cluster/issues/3) |

## Open decisions

- What happens to the old Proxmox-era repos (`k3s-infra`,
  `k3s-nixos-proxmox-prod`).
- Network extras: Wi-Fi access point, guest and IoT VLANs, a DMZ, LACP over the
  spare router ports, jumbo frames on the storage VLAN.
