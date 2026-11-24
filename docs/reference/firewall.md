---
icon: lucide/shield
---

# Firewall

The ports the hosts and VMs open, each on one interface (NixOS firewalls in
this repo), and the Cloudflare Gateway rules for remote access. What may
talk between VLANs is decided by the router.

!!! network "On the network docs: VLAN policy"

    What each VLAN may reach, the WAN forwards and the router and switch monitoring access, enforced by OPNsense.

    [Network firewall](https://github.com/jurrebuunk/hgd1-network/blob/main/docs/firewall.md){ .md-button }

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
| `br-stor` | TCP 8428 | VictoriaMetrics remote write from k3s (vmagent in `hgd1-k8s`) |
| `br-stor` | TCP 9428 | VictoriaLogs ingest from the VMs and from k3s (Vector in `hgd1-k8s`) |
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

Pods reach the hosts' storage IPs on 8428 and 9428 for monitoring
(collectors in `hgd1-k8s`, see the [Kubernetes docs](https://jurrebuunk.github.io/hgd1-k8s/concepts/monitoring/)).
