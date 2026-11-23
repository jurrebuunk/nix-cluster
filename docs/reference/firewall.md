---
icon: lucide/shield
---

# Firewall

!!! repo "Lives in its own repo: hgd1-network"

    This page covers **the firewall policy** on the hgd1 cluster: how it fits in and how I
    use it here. Code, development, releases and the full documentation are in
    the repo (private).

    [:fontawesome-brands-github: jurrebuunk/hgd1-network](https://github.com/jurrebuunk/hgd1-network){ .md-button .md-button--primary }

What may talk to what. OPNsense enforces the VLAN policy (its rules are code in
[`hgd1-network`](https://github.com/jurrebuunk/hgd1-network)); NixOS firewalls on the hosts and VMs open only the ports below, each
on one interface (this repo).

## VLAN policy

Everything between VLANs is denied unless listed.

| From | Allowed | Blocked |
| --- | --- | --- |
| mgmt (10) | Everything internal, internet | – |
| infra (20) | Internet, DNS and NTP on OPNsense | Other internal |
| infra: `10.10.20.11–13` only | mgmt, k8s, users (remote access) | storage (not routed) |
| k8s (40) | Internet, DNS and NTP on OPNsense | mgmt, infra, users |
| users (100) | Internet; TCP 80/443 to k8s load balancers `.200–.249` | mgmt, infra, k8s nodes |
| WAN (home) | Sunshine forwards to `10.10.100.50` (below) | Everything else |

The remote-access exception uses the OPNsense aliases `HGD1_TUNNEL_HOSTS`
(`10.10.20.11–13`) and `HGD1_TUNNEL_DESTS` (`10.10.10.0/24`,
`10.10.40.0/24`, `10.10.100.0/24`), in a rule placed above "INFRA deny other
private destinations".

## WAN forwards

| Proto | Ports | To |
| --- | --- | --- |
| TCP | 47984, 47989, 48010 | `10.10.100.50` (Sunshine) |
| UDP | 47998–48000, 48002, 48010 | `10.10.100.50` |

Source: the whole home network `192.168.2.0/24`, destination the WAN address
`192.168.2.12`. Not forwarded: 47990 (Sunshine admin), RDP, discovery.
"Block private networks" stays **off** on WAN.

## Hosts

| Interface | Port | Service |
| --- | --- | --- |
| `enp2s0` | TCP 22 | SSH |
| `enp2s0` | UDP 5353 | mDNS (Avahi) |
| `br-stor` | TCP 3300, 6789 | Ceph monitors |
| `br-stor` | TCP 6800–7300 | Ceph OSDs and managers |
| `br-stor` | TCP 7480 | RGW (S3 backend) |
| `br-stor` | TCP 9283 | Ceph manager metrics |
| `br-stor` | TCP 443 | S3 endpoint (HAProxy) |
| `br-stor` | VRRP | Only from the other two hosts, TTL 255 |
| `br-stor` | TCP 9428 | VictoriaLogs ingest from the VMs |
| `enp2s0` | TCP 8428 | VictoriaMetrics: queries, remote write from peers |
| `enp2s0` | TCP 9428 | VictoriaLogs: queries, ingest from peers |
| `enp2s0` | TCP/UDP 514 | Syslog from router and switch |
| `enp2s0` | VRRP | Monitoring VIP, only from the other two hosts, TTL 255 |
| `enp2s0` | TCP 443 | Platform API (`api.lan.buunk.org`) |
| `enp2s0` | VRRP | API VIP (id 21), only from the other two hosts, TTL 255 |
| `127.0.0.1` | 8405, 8429, 9100, 9115, 9116, 9598, 9633, 20241 | Exporters and agents, local only |
| `br-k8s` | – | All input dropped; no routing between bridges and host |

## k3s VMs

| Interface | Port | Service | Nodes |
| --- | --- | --- | --- |
| `k8s` | TCP 22 | SSH | all |
| `k8s` | TCP 10250 | kubelet | all |
| `k8s` | UDP 8472 | flannel VXLAN | all |
| `k8s` | TCP 6443 | Kubernetes API | servers |
| `k8s` | TCP 2379–2380 | etcd | servers |
| `k8s` | VRRP | Only from the other servers, TTL 255 | servers |
| `cni0`, `flannel.1` | all | Pod traffic (trusted) | all |
| `storage` | TCP 9100 | node_exporter, scraped by the owning host | all |

## Cloudflare Gateway

| Order | Rule |
| --- | --- |
| 500 | Block `10.10.30.0/24` (storage) for everyone |
| 1000 | Allow `10.10.0.0/16` for my email |
| 2000 | Block `10.10.0.0/16` for everyone else |

ICMP is proxied but can't be filtered by Gateway.

## Devices

| Device | Open for monitoring |
| --- | --- |
| OPNsense | `10.10.10.1:9100` node_exporter (reached by the hosts through the remote-access rule) |
| Aruba | SNMP v2c read-only (`operator restricted`), community in `secrets/snmp-community.age` |

Rules for k3s workloads (for example K8S → `10.10.20.20:443` for the web UI)
are added in `hgd1-network` too.
