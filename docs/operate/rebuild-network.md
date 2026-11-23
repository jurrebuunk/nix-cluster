---
icon: lucide/cable
---

# Rebuild the network

This is how I brought the network up the first time. You only need it to
rebuild the site after a total loss, or to build a similar one. The live
network is already in its final state; don't repeat these steps on it.

Only N0 is by hand. Everything the router and switch get after that comes
from the playbooks in [`hgd1-network`](https://github.com/jurrebuunk/hgd1-network); this page explains the order and the reasons.

The order matters because you must never lock yourself out: the laptop starts
on the home network (the router's WAN side) and only switches to WARP at the
very end.

## Overview

| Step | What | Who |
| --- | --- | --- |
| N0 | Cabling, OPNsense install, SSH keys, temporary WAN access | By hand |
| N1 | OPNsense base: firmware, hostname, Unbound with DNSSEC, NTP, backup | `hgd1-network` |
| N2 | VLAN interfaces 20/40/100, DHCP on mgmt and users, outbound NAT | `hgd1-network` |
| N3 | Switch: VLANs, management on `10.10.10.2`, port roles; hypervisor ports stay on VLAN 10 | `hgd1-network` |
| N4 | Firewall rules per the [policy](../reference/firewall.md); temporary WAN rules stay | `hgd1-network` |
| N5 | Move each hypervisor to its static addresses, one at a time | [Moving a host](#moving-a-host) |
| N6 | Verify: inter-VLAN tests from every VLAN, host internet, reboot router and switch | By hand, from test clients |
| N7 | Remote access, then remove the temporary WAN rules (`hgd1-network`) | [Remote access](../concepts/remote-access.md#setting-it-up-again) |

## Bootstrap (N0)

**Cabling.**

- Home router uplink → the OPNsense **onboard** NIC (WAN).
- OPNsense PCIe port 1 → a switch port (the trunk). Note which port.
- PCIe ports 2 and 3 → the switch, unused for now.
- Note which switch ports go to each hypervisor.

**OPNsense install.** Install from USB and set a strong root password. At the
console, assign WAN to the onboard NIC and LAN to PCIe port 1 (no VLANs yet).
Give LAN `10.10.10.1/24` with a DHCP pool `.100–.199`. WAN can use DHCP;
reserve its address on the home router.

**SSH access from the home network.** These rules are temporary and get removed in N7.

1. Enable SSH, allow root login, **disable password login**, and add your
   public key to the `root` user.
2. On WAN, untick "Block private networks" (your home network *is* private).
3. Add WAN pass rules from `192.168.2.0/24` to the WAN address on TCP 22 and
   443, and to `10.10.0.0/16` on TCP 22.
4. Check from the laptop: `ssh root@<wan-ip> 'uname -a'` must not ask for a
   password.

**Switch.** Give it an admin password and enable SSH (`ip ssh` and
`write memory` on AOS-S). It gets a `10.10.10.x` lease from OPNsense. Check:
`ssh -J root@<wan-ip> manager@<switch-ip>`. Install your SSH key for the admin
user too.

From here on, set `JUMP=root@<wan-ip>`; `scripts/deploy.sh` and the other
scripts accept it until N7. Then run the `hgd1-network` playbooks for N1–N4
from the laptop through the same jump host.

**If you lock yourself out:** plug the laptop into any switch port that is
still on the default VLAN. It gets a `10.10.10.x` lease, and the OPNsense web
UI at `https://10.10.10.1` is always allowed from LAN.

## Moving a host

During N0–N4 the hypervisors run on temporary DHCP leases in `10.10.10.x`.
Each one moves to its final addresses in a single reboot, guarded by a timer
that reverts automatically if you can't confirm the new state.

For `hgd1-hv01` (then hv02, then hv03, never in parallel):

1. **Arm the guard** (`modules/rollout-safety.nix`). It reverts to the saved
   generation and reboots ten minutes after boot unless you disarm it.

    ```sh
    ssh -J "$JUMP" jurre@10.10.10.<lease> 'sudo sh -c '\''umask 077; mkdir -p /var/lib/n5-rollout/before; readlink -f /run/current-system > /var/lib/n5-rollout/before/current-system; touch /var/lib/n5-rollout/pending'\'''
    ```

2. **Install the new config for the next boot**, through the temporary lease:

    ```sh
    TARGET=10.10.10.<lease> scripts/deploy.sh hgd1-hv01 boot
    ```

3. **Reboot in a minute, and switch its port in that minute** to untagged 20,
   tagged 30 and 40 (the port role from `hgd1-network`):

    ```sh
    ssh -J "$JUMP" jurre@10.10.10.<lease> 'sudo systemd-run --on-active=60 systemctl reboot'
    ```

4. **Verify** on the new address: hostname, `enp2s0` with `10.10.20.11/24`,
   `br-stor` with `10.10.30.11/24`, `br-k8s` up without an address, chrony
   using `10.10.20.1`, no failed units.
5. **Disarm** only after all of that passed:

    ```sh
    ssh -J "$JUMP" jurre@10.10.20.11 'sudo rm /var/lib/n5-rollout/pending; sudo systemctl stop n5-rollback.timer'
    ```

If the host does not come back, put its switch port back on untagged 10 and
wait: the guard restores the old generation, which uses DHCP on VLAN 10. If it
failed before systemd started, pick the previous generation in the boot menu.

After all three hosts, they must ping each other on `10.10.30.0/24`.

## Verification (N6)

From throwaway clients on every VLAN I tested DHCP and its options, DNS, NTP,
NAT, every allowed and blocked path in the policy, SSH isolation of the hosts,
load balancer boundaries, and that storage reaches all hosts on layer 2
without any router interface. Then I rebooted the router and the switch and
checked that everything came back from saved configuration.

!!! warning "Test addresses"

    Never reuse a live address for a test client. `10.10.40.11` was a test
    fixture during N6 and is now `hgd1-k8m01`. Check the inventory first.

## Related

- [Network](../concepts/network.md) · [Router and switch](router-and-switch.md) · [`hgd1-network`](https://github.com/jurrebuunk/hgd1-network)
