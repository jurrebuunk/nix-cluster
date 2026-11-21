# Network plan (site hgd1)

Router: OPNsense (1 onboard NIC + 4-port PCIe NIC). Switch: Aruba.
Scope now: cluster networks and a wired user LAN. WiFi, guest, IoT and DMZ are
future work (see the end).

You do step N0 by hand ([BOOTSTRAP.md](BOOTSTRAP.md)). Claude does N1–N7 over
SSH from the laptop, which stays on the home WiFi (OPNsense WAN side) until N7.

## Physical layout

```
home router (192.168.2.0/24, internet)
   │  uplink cable
   ▼
OPNsense  onboard NIC ── WAN
          PCIe port 1 ── LAN trunk ──────────┐
          PCIe port 2 ── (spare, later LAGG) ┤ switch
          PCIe port 3 ── (spare, later LAGG) ┤
          PCIe port 4 ── unused              │
                                             ├─ patch ─ hgd1-hv01
                                             ├─ patch ─ hgd1-hv02
                                             ├─ patch ─ hgd1-hv03
                                             └─ user ports (wired LAN)
```

The internet uplink goes into the **OPNsense onboard NIC**, not into the switch.
WAN then never touches the switch, and the home network can never leak into
the internal VLANs. If the cable cannot reach the router, the alternative is a
dedicated WAN VLAN on the switch; that needs switch configuration before
OPNsense is connected, so avoid it if possible.

The two spare PCIe↔switch links are unassigned in OPNsense (no traffic, no
loop) until they are bundled with port 1 into an LACP LAGG (future).

## Addressing and VLANs

Site range `10.10.0.0/16`; third octet = VLAN ID. Avoid `10.42.0.0/16` and
`10.43.0.0/16` (k3s pods/services).

| VLAN | Name | Subnet | Gateway | DHCP | Members |
| --- | --- | --- | --- | --- | --- |
| 10 | mgmt | 10.10.10.0/24 | 10.10.10.1 | small pool .100–.199 | OPNsense, switch, (later AP, AMT) |
| 20 | infra | 10.10.20.0/24 | 10.10.20.1 | no | hypervisors, compute01 host |
| 30 | storage | 10.10.30.0/24 | none | no | Ceph: hosts + k3s VMs, **not routed** |
| 40 | k8s | 10.10.40.0/24 | 10.10.40.1 | no | k3s VMs, LB IPs .200–.249 |
| 100 | users | 10.10.100.0/24 | 10.10.100.1 | .100–.249 | wired users, Windows gaming VM |

VLAN 10 is untagged on the router↔switch trunk (it is the bootstrap LAN);
20, 40 and 100 are tagged. VLAN 30 never reaches the router.

### Fixed addresses

| Name | VLAN 10 | VLAN 20 | VLAN 30 | VLAN 40 |
| --- | --- | --- | --- | --- |
| OPNsense (`hgd1-fw01`) | .1 | .1 | – | .1 |
| Switch (`hgd1-sw01`) | .2 | – | – | – |
| hgd1-hv01 | – | .11 | .11 | – |
| hgd1-hv02 | – | .12 | .12 | – |
| hgd1-hv03 | – | .13 | .13 | – |
| hgd1-k8m01–03 | – | – | .21–.23 | .11–.13 |
| hgd1-k8w01–02 | – | – | .31–.32 | .21–.22 |

The separate `nix-compute01` host is static **10.10.20.50** (VLAN 20).
Its `win11-gaming` VM uses **10.10.100.50** (VLAN 100), reserved for MAC
`52:54:00:39:2c:95`, outside the dynamic pool. The VM bridge is unnumbered on
the host; host firewall rules prevent routing around OPNsense between VLANs.

Internal DNS zone: `hgd1.lan.buunk.org`, served by OPNsense (Unbound).

### Switch ports

| Port role | Switch ports | Untagged | Tagged |
| --- | --- | --- | --- |
| Router trunk (PCIe port 1 / igb0) | 14 | 10 | 20, 40, 100 |
| Cluster hypervisors | 5, 7, 9 | 20 after N5; **10 during bootstrap** | 30, 40 |
| compute01 host + gaming VM | 19 | 20 | 100 |
| Wired users / setup | 2, 4, 48 | 100 | – |
| Management recovery | 1 | 10 | – |
| Router spare links | 16, 18 | 999, disabled | – |
| All other ports | remaining ports | 999, disabled | – |

Switch: HP/Aruba 2530-48G J9775A. Verify the cluster host MACs before assigning
hv01–03 to slots 5/7/9; port order alone does not identify a host. WAN stays on
the router's onboard re0 and does not pass through the Aruba.

### Firewall policy

| From | Allowed | Blocked |
| --- | --- | --- |
| mgmt (10) | everything internal, internet | – |
| infra (20) | internet (Nix caches), DNS/NTP on OPNsense | mgmt, users |
| k8s (40) | internet (registries), DNS/NTP on OPNsense | mgmt, infra, users |
| users (100) | internet; k8s LB/ingress IPs on 80/443 | mgmt, infra, k8s nodes |
| WAN | during build: SSH/HTTPS from 192.168.2.0/24 to OPNsense and SSH to the internal nets; permanently: Sunshine streaming from the whole home subnet to the gaming VM via DNAT (below) | everything else |

Admin access after N7: Cloudflare Zero Trust. `cloudflared` on all three
hypervisors routes `10.10.0.0/16`; the laptop uses the WARP client (see N7).
Locally, a mgmt switch port or the OPNsense console always works.

### Gaming streaming: permanent home-WAN exception

- Source: **all 192.168.2.0/24**, not selected client IPs.
- Destination: OPNsense WAN address (currently **192.168.2.12**).
- DNAT target: **10.10.100.50**, same internal/external port numbers.
- TCP: **47984, 47989, 48010**.
- UDP: **47998–48000, 48002, 48010**.
- Destination NAT rules register their matching firewall pass rules.
- No WAN forwards for the admin UI (47990), RDP (3389), or discovery multicast.

USERS clients reach the VM directly at 10.10.100.50. Home/WAN Moonlight clients
manually add 192.168.2.12; no home-router static route is needed. Pairing remains
Sunshine's normal per-client PIN/certificate process. This is local home access,
not public-internet streaming. Reserve the WAN address for onboard MAC
`90:1b:0e:fa:70:dd` on the home router.

**Do not re-enable WAN "Block private networks" in N7:** the WAN is the private
home network, so that blanket block would override the streaming exception.
Default-deny plus the narrow streaming rules enforce the boundary instead.

---

## N0: Bootstrap (you)

Follow [BOOTSTRAP.md](BOOTSTRAP.md): cabling, OPNsense install with WAN and an
untagged LAN on `10.10.10.1/24`, SSH key access from the WAN side, switch
reachable over SSH through OPNsense.

**Done when:** `ssh root@<opnsense-wan-ip>` and
`ssh -J root@<opnsense-wan-ip> <user>@<switch-ip>` work from the laptop.

## N1: OPNsense base

- Firmware update, hostname `hgd1-fw01`, domain `hgd1.lan.buunk.org`, timezone,
  NTP.
- Unbound DNS with DNSSEC; register DHCP leases; host overrides for fixed
  addresses.
- Rename LAN to `MGMT`; DHCP pool `10.10.10.100–199`.
- Config backup exported to the laptop before every larger change.

**Done when:** OPNsense resolves internal and external names, and a backup
exists.

## N2: OPNsense VLANs and DHCP

- VLAN interfaces 20 (`INFRA`), 40 (`K8S`), 100 (`USERS`) on PCIe port 1,
  addresses as in the table.
- DHCP only on MGMT and USERS.
- Outbound NAT (automatic) for all internal nets.

**Done when:** all interfaces are up in OPNsense; nothing changes on the switch
yet.

## N3: Switch

- Admin hardening: SSH only, own admin user, SNTP from OPNsense, hostname
  `hgd1-sw01`.
- Create VLANs 10, 20, 30, 40, 100, 999.
- Move switch management to VLAN 10 with static `10.10.10.2` (done carefully:
  the router port keeps working untagged throughout).
- Port roles as in the table; unused ports to 999.
- Hypervisor ports are switched last, in N5, one at a time.

**Done when:** a laptop on a user port gets a `10.10.100.x` lease and internet;
switch reachable at `10.10.10.2`.

## N4: Firewall rules

- Rules per interface as in the policy table, default deny between VLANs.
- Keep the temporary WAN management rules until N7.

**Done when:** a user port reaches the internet but not `10.10.20.0/24`, and
management access from the laptop still works.

## N5: Move the hypervisors (with nix-cluster)

- NixOS side is configured (`inventory.nix`, `modules/network.nix`): host on
  untagged VLAN 20 (`10.10.20.1x`, gateway `.1`, DNS/NTP OPNsense),
  `enp2s0.30` → `br-stor` with `10.10.30.1x`, `enp2s0.40` → `br-k8s` without
  a host address. Ceph uses `10.10.30.0/24`, its ports open on `br-stor` only.
- Per host, as in [ROLLOUT.md](../ROLLOUT.md) part B:
  `TARGET=<temporary 10.10.10.x lease> scripts/deploy.sh <host> boot` while it
  is still reachable, switch its port to untagged 20 / tagged 30,40, reboot,
  verify; then the next host.
- Fallback: previous boot generation at the console (DHCP config) and the
  switch port back to untagged 10.

**Done when:** all three hosts are reachable at `10.10.20.11–13` through
OPNsense and ping each other on `10.10.30.0/24`.

## N6: Verify

- Inter-VLAN policy tests from each VLAN.
- Host internet access (`nix build` pulling from cache.nixos.org).
- Reboot OPNsense and the switch once; everything comes back.

## N7: Remote access (Cloudflare) and close bootstrap WAN management

Goal: reach the whole internal network from anywhere (school, …) as if on the
LAN, independent of k3s. Nothing inside the network depends on it.

- `cloudflared` on **all three hypervisors** (one tunnel, three replicas), as
  `modules/remote-access.nix` in `nix-cluster` using `services.cloudflared`;
  tunnel credentials as an agenix secret. Any one host keeps access up.
  Setup steps: [REMOTE-ACCESS.md](REMOTE-ACCESS.md).
- Tunnel private network route: `10.10.0.0/16`.
- Laptop: Cloudflare One (WARP) client enrolled in your Zero Trust org.
- Zero Trust settings:
  - Split Tunnels: remove `10.10.0.0/16` from the default `10.0.0.0/8` exclude.
  - Local Domain Fallback: `hgd1.lan.buunk.org` → OPNsense DNS.
  - Policy: only your account may use the private network.
- OPNsense: allow `10.10.20.11–13` to reach mgmt, infra, k8s and users
  (storage stays unreachable; it is not routed).
- Then remove **only temporary bootstrap WAN management** rules (router SSH/HTTPS
  and internal SSH). Preserve the Sunshine DNAT/registered pass rules. Leave
  "Block private networks" **off** on this private home-WAN; all other inbound
  traffic remains default-denied. Final config backup of OPNsense and the switch.

Differences from a real LAN port: no `.local`/mDNS discovery, no DHCP address
of your own, internal servers see traffic from the hypervisors, and per-user
control lives in Zero Trust policies. Server-to-laptop connections need
Cloudflare Mesh (only add if ever needed). Free plan: 1 user and 3 replicas are
far under the limits (50 users).

**Done when:** from outside the home network, `ssh` to a hypervisor, the
OPNsense web UI and an internal name in `hgd1.lan.buunk.org` work through WARP
with one hypervisor powered off; the WAN side has no bootstrap management
access, while home Moonlight streaming through 192.168.2.12 still works.

After N7, continue with cluster [PLAN.md](../PLAN.md) step 2 (Ceph).

---

## Future

- Cloudflare Mesh, only if connections back to the laptop are ever needed.
- WiFi AP on VLAN 10 management, SSIDs mapped to VLAN 100 / 110 guest /
  120 IoT.
- Guest (110) and IoT (120) VLANs and rules.
- DMZ (50) if something must be exposed outside k3s ingress.
- LACP LAGG over PCIe ports 1–3.
- Jumbo frames (MTU 9000) on VLAN 30 if the switch supports it.
