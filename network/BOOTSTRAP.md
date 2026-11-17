# Network bootstrap (you, by hand)

Goal: the minimum so that Claude can reach OPNsense and the Aruba switch over
SSH from the laptop on the home WiFi. Everything else is done from there (see
[PLAN.md](PLAN.md), steps N1–N7). Leave WiFi out for now.

Time: about an hour, most of it the OPNsense install.

## 1. Cabling

- [ ] **Internet uplink** (cable from the home router): move it **out of the
      switch** and into the **OPNsense onboard NIC**. This becomes WAN.
- [ ] **PCIe port 1 → switch**: this becomes LAN. Note which switch port it
      lands in.
- [ ] PCIe ports 2 and 3 → switch: leave them cabled; they stay unused for now.
- [ ] Hypervisors → switch via the patch panel: leave as is. Once OPNsense LAN
      is up they get temporary `10.10.10.x` DHCP addresses; that is expected.
- [ ] Note which switch ports go to `hgd1-hv01` (pve0), `hgd1-hv02` (pve1) and
      `hgd1-hv03` (pve2).

Keep a monitor and keyboard for the OPNsense box.

## 2. OPNsense install

- [ ] Install OPNsense (latest release) from USB, using the installer user
      `installer`/`opnsense`. Set a strong root password.
- [ ] At the console, **Assign interfaces** (option 1):
      - no VLANs yet (answer `n`),
      - WAN = the onboard NIC, LAN = PCIe port 1.
      Use auto-detect (unplug/replug the cable when asked) if you are unsure
      which name (`igb0`, `em0`, `re0`, …) is which port.
- [ ] **WAN address** (option 2, WAN): DHCP is fine. Then on the home router,
      make a **DHCP reservation** for the OPNsense WAN MAC so its address never
      changes. Avoid `192.168.2.10` (in use).
- [ ] **LAN address** (option 2, LAN): `10.10.10.1`, prefix `24`, no upstream
      gateway, **enable DHCP server** with range `10.10.10.100`–`10.10.10.199`.

## 3. OPNsense access from the laptop

From a device on the LAN side (e.g. the laptop plugged into a switch port for a
moment, browsing to `https://10.10.10.1`), or after step 3c via WAN:

- [ ] **a. SSH** — System → Settings → Administration → Secure Shell:
      - Enable Secure Shell: on
      - Permit root user login: on
      - Permit password login: **off**
      - Listen interfaces: All (default)
- [ ] **b. SSH key** — System → Access → Users → `root` → Authorized keys:
      ```
      ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDfML1tz4bMJ7uAoIS5Hhd3cTE95X5QdaEJ8hR/1gWnE jurre@b302.nl
      ```
      Save.
- [ ] **c. Allow management from the home network** (temporary, removed in N7):
      - Interfaces → WAN: **untick "Block private networks"** (and leave "Block
        bogon networks" on). Save, Apply.
      - Firewall → Rules → WAN → Add:
        Action Pass, Protocol TCP, Source `192.168.2.0/24`,
        Destination "WAN address", Destination port **22**. Save.
      - Same rule again with port **443** (web UI). Apply.
      - Firewall → Rules → WAN → Add:
        Action Pass, Protocol TCP, Source `192.168.2.0/24`,
        Destination `10.10.0.0/16`, Destination port **22**. Apply.
        (Lets the laptop reach the switch and hosts directly, once it has a
        route: `sudo ip route add 10.10.0.0/16 via <opnsense-wan-ip>`.
        Without that route, use OPNsense as SSH jump host instead.)
- [ ] **d. Firmware**: System → Firmware → Updates → Check / Update.

**Check from the laptop on the home WiFi:**
```sh
ssh root@<opnsense-wan-ip> 'uname -a'
```
No password prompt may appear.

## 4. Aruba switch

- [ ] If the switch was used before, factory reset it (see its manual; usually
      hold the Reset + Clear buttons, or `erase startup-config` on the console).
- [ ] With the factory config, all ports are in VLAN 1 and the switch takes a
      DHCP address from OPNsense. Find it in OPNsense: Services → DHCPv4 →
      Leases (`10.10.10.1xx`), or on the switch console.
- [ ] Set an admin password and make sure SSH is enabled (console cable or web
      UI on the switch's IP):
      - **AOS-S** (2530, 2540, 2930F, …):
        ```
        configure
        password manager user-name admin plaintext <password>
        ip ssh
        write memory
        ```
      - **AOS-CX** (6000, 6100, 6200, …):
        ```
        configure terminal
        user admin group administrators password plaintext <password>
        ssh server vrf default
        exit
        write memory
        ```
      - **Instant On** (1830, 1930, 1960): there is no SSH CLI. Stop here and
        tell Claude; the switch then gets configured through its web UI.
- [ ] Optional: install the laptop's SSH key for the admin user so no password
      is needed.

**Check from the laptop on the home WiFi:**
```sh
ssh -J root@<opnsense-wan-ip> admin@<switch-ip>      # via OPNsense as jump host
# or, with the laptop route from step 3c:
ssh admin@<switch-ip>
```

## 5. Hand over to Claude

Send:

- [ ] OPNsense WAN IP: `192.168.2.___`
- [ ] Switch IP: `10.10.10.___`, exact model (label on the back, e.g.
      "Aruba 2930F-24G-PoE+ JL261A"), firmware version if known
- [ ] Switch username; password in a file **outside the repo** (e.g.
      `~/.secrets/aruba-admin`) or SSH key installed — not in the chat
- [ ] Switch port numbers for: OPNsense PCIe ports 1–3, `hgd1-hv01–03`, and
      the ports meant for wired users

## If something goes wrong

- **Locked out from WAN:** plug the laptop into any switch port (VLAN 1 = LAN),
  it gets a `10.10.10.x` lease; the web UI at `https://10.10.10.1` is always
  allowed from LAN (anti-lockout rule).
- **No internet behind OPNsense:** check that WAN has an address and gateway
  (Interfaces → Overview) and that the home router's cable is in the onboard
  NIC.
- **The hypervisors disappear from `pveN.home`:** expected; they now have
  `10.10.10.x` leases from OPNsense (Services → DHCPv4 → Leases).
