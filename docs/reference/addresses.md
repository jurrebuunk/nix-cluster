# Addresses and names

Every fixed address in one place. The source of truth is
[`inventory.nix`](https://github.com/jurrebuunk/nix-hgd1-cluster/blob/main/inventory.nix)
for hosts and VMs, and the OPNsense configuration for the rest. DNS names are
in `lan.buunk.org`.

## VLANs

| VLAN | Name | Subnet | Gateway | DHCP |
| --- | --- | --- | --- | --- |
| 10 | mgmt | `10.10.10.0/24` | `10.10.10.1` | `.100–.199` |
| 20 | infra | `10.10.20.0/24` | `10.10.20.1` | no |
| 30 | storage | `10.10.30.0/24` | none (not routed) | no |
| 40 | k8s | `10.10.40.0/24` | `10.10.40.1` | no |
| 100 | users | `10.10.100.0/24` | `10.10.100.1` | `.100–.249` |
| – | home / WAN | `192.168.2.0/24` | home router | home router |

Kept free: `10.42.0.0/16` (k3s pods) and `10.43.0.0/16` (k3s services).

## Fixed addresses

| Name | mgmt (10) | infra (20) | storage (30) | k8s (40) | other |
| --- | --- | --- | --- | --- | --- |
| `hgd1-fw01` (OPNsense) | `10.10.10.1` | `10.10.20.1` | – | `10.10.40.1` | users `10.10.100.1`, WAN `192.168.2.12` |
| `hgd1-sw01` (Aruba) | `10.10.10.2` | – | – | – | – |
| `hgd1-hv01` | – | `10.10.20.11` | `10.10.30.11` | – | – |
| `hgd1-hv02` | – | `10.10.20.12` | `10.10.30.12` | – | – |
| `hgd1-hv03` | – | `10.10.20.13` | `10.10.30.13` | – | – |
| `hgd1-gpu1` | – | `10.10.20.50` | – | – | – |
| `win11-gaming` | – | – | – | – | users `10.10.100.50` |
| `hgd1-k8m01` | – | – | `10.10.30.21` | `10.10.40.11` | – |
| `hgd1-k8m02` | – | – | `10.10.30.22` | `10.10.40.12` | – |
| `hgd1-k8m03` | – | – | `10.10.30.23` | `10.10.40.13` | – |
| `hgd1-k8w01` | – | – | `10.10.30.31` | `10.10.40.21` | – |
| `hgd1-k8w02` | – | – | `10.10.30.32` | `10.10.40.22` | – |

## Floating and service addresses

| Name | Address | Owned by |
| --- | --- | --- |
| `s3.lan.buunk.org` | `10.10.30.10:443` | Keepalived on the hosts (VRRP id 30) |
| `k8s.lan.buunk.org` | `10.10.40.10:6443` | Keepalived on the k3s servers (VRRP id 40) |
| Kubernetes load balancers | `10.10.40.200–249` | Reserved for step 6 |
| Ceph monitors | `10.10.30.11–13`, ports 3300 (v2) and 6789 (v1) | Ceph |
| RGW (direct, diagnostics) | `10.10.30.11–13:7480` | Ceph |
| Ceph manager metrics | `<storage-ip>:9283` | Active manager |

## MAC addresses

| Device | MAC |
| --- | --- |
| `hgd1-hv01` `enp2s0` | `fc:3f:db:10:c6:c9` |
| `hgd1-hv02` `enp2s0` | `fc:3f:db:0a:b1:c3` |
| `hgd1-hv03` `enp2s0` | `fc:3f:db:0a:c1:42` |
| OPNsense WAN (`re0`) | `90:1b:0e:fa:70:dd` |
| `win11-gaming` | `52:54:00:39:2c:95` |
| VM k8s NIC | `02:00:00:40:00:<id in hex>` |
| VM storage NIC | `02:00:00:30:00:<id in hex>` |

## Switch ports

| Port | Connected to |
| --- | --- |
| 1 | Management recovery (untagged 10) |
| 2, 4, 48 | Wired users (untagged 100) |
| 5 / 7 / 9 | `hgd1-hv01` / `hgd1-hv02` / `hgd1-hv03` (untagged 20, tagged 30, 40) |
| 14 | OPNsense trunk `igb0` (untagged 10, tagged 20, 40, 100) |
| 16, 18 | Spare router links, disabled |
| 19 | `hgd1-gpu1` (untagged 20, tagged 100) |

## Remote access

| Item | Value |
| --- | --- |
| Zero Trust team | `buunk` (`buunk.cloudflareaccess.com`) |
| Tunnel | `hgd1-admin`, ID in `inventory.nix` → `remoteAccess.tunnelId` |
| Routed through the tunnel | `10.10.0.0/16` (storage blocked in Gateway) |
