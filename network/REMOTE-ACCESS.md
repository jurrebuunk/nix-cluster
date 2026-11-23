# Remote access through Cloudflare (network plan N7)

**Status: done 2026-11-23.** Tunnel `hgd1-admin`, 3 connectors on hv01–03.

Reach the whole site network (`10.10.0.0/16`) from anywhere, as if on the LAN:
SSH, OPNsense and switch web UIs, the k8s API, internal apps and internal names.
`cloudflared` runs on all three hypervisors (one tunnel, three replicas); the
laptop uses the Cloudflare One (WARP) client. Nothing in the cluster depends on
this path.

Config: [`modules/remote-access.nix`](../modules/remote-access.nix), switched on
by `remoteAccess.tunnelId` in [`inventory.nix`](../inventory.nix). Do this after
network plan N4–N6, with the hosts on `10.10.20.11–13`.

## 1. Zero Trust organisation (dashboard, once)

- [x] Cloudflare dashboard → Zero Trust: create the organisation (team name)
      on the **Free** plan. Cloudflare may ask for a payment method even on
      Free.
- [x] Settings → Authentication: keep **One-time PIN** (or add GitHub/Google).
- [x] Settings → WARP Client → Device enrollment permissions: a rule that only
      allows **your email address**.

## 2. Tunnel (laptop, in this repo)

```sh
nix develop
cloudflared tunnel login                     # browser; pick the buunk.org zone
cloudflared tunnel create hgd1-admin         # prints the tunnel UUID
cloudflared tunnel route ip add 10.10.0.0/16 hgd1-admin
```

`create` writes the credentials to `~/.cloudflared/<UUID>.json`.

- [x] Put the UUID in `inventory.nix`: `remoteAccess.tunnelId = "<UUID>";`
- [x] Encrypt the credentials for the laptop and all three hosts:
      ```sh
      cd secrets
      EDITOR="cp $HOME/.cloudflared/<UUID>.json" agenix -e cloudflared-tunnel.age
      cd ..
      ```
- [x] Keep a copy of the JSON in your password manager, then delete
      `~/.cloudflared/<UUID>.json`.
- [x] Commit, then deploy one host at a time:
      ```sh
      scripts/deploy.sh hgd1-hv01 switch
      ssh jurre@10.10.20.11 'systemctl status "cloudflared-tunnel-*" --no-pager'
      ```
      Repeat for `hgd1-hv02` and `hgd1-hv03`. The dashboard (Networks →
      Tunnels → hgd1-admin) shows 3 connectors.

## 3. WARP client settings (dashboard)

- [x] Settings → WARP Client → Device settings → Default profile → **Split
      Tunnels**: **Include** mode with only `10.10.0.0/16` and the team domain
      `buunk.cloudflareaccess.com`. Everything else, including normal internet
      traffic and the home network, goes direct; WARP only carries site traffic.
      On the USERS VLAN, run `warp-cli disconnect` so site traffic goes straight
      through OPNsense instead of out to Cloudflare and back (`warp-cli connect`
      when away).
- [x] Same profile → **Local Domain Fallback**: add `lan.buunk.org` with
      DNS server `10.10.20.1` (OPNsense).
- [x] Traffic policies → Traffic settings → **Proxy**: TCP, UDP and ICMP on (needed for WARP traffic
      to private networks; ICMP is for ping and cannot be filtered by Gateway).
- [x] Gateway → Firewall policies → Network: block `10.10.30.0/24` (storage,
      precedence 500); allow `10.10.0.0/16` for your email; block
      `10.10.0.0/16` for everyone else.

## 4. OPNsense

- [x] Firewall → Rules → INFRA: allow source `10.10.20.11–13` to MGMT, K8S and
      USERS (everything internal except storage, which is not routed). Done as aliases
      `HGD1_TUNNEL_HOSTS` → `HGD1_TUNNEL_DESTS`, above the INFRA deny rule.
- [x] Once remote access works: remove **only bootstrap management** WAN rules
      (router 22/443 from `192.168.2.0/24`, SSH to `10.10.0.0/16`). Preserve the
      permanent Sunshine DNAT/registered pass rules from the whole home subnet
      to `10.10.100.50` (TCP 47984/47989/48010; UDP 47998–48000/48002/48010).
- [x] Leave WAN **"Block private networks" off**: this WAN is the private home
      network, and the blanket block would break Moonlight clients. Default-deny
      plus the explicit streaming exceptions remain the inbound policy.

## 5. Laptop

- [x] Install the WARP client. On NixOS: `services.cloudflare-warp.enable = true;`
      in the laptop config, then `warp-cli registration new <team-name>` and
      `warp-cli connect`. On other systems: the Cloudflare One app.

## Verify (from outside the home network, e.g. a phone hotspot)

```sh
warp-cli status                                   # Connected
ssh jurre@10.10.20.11 hostname                    # hgd1-hv01
getent hosts hgd1-hv02.lan.buunk.org            # 10.10.20.12
curl -kI https://10.10.10.1                       # OPNsense web UI
```

Then power off (or stop `cloudflared` on) one hypervisor and repeat: access must
keep working through the other two. Also test Moonlight from the home WAN after
removing bootstrap rules: manually add `192.168.2.12`, not the VM's private
address. USERS clients use `10.10.100.50` directly. Do not expose the Sunshine
admin UI or RDP through these streaming rules.

## Notes

- Internal servers see remote traffic coming from a hypervisor
  (`10.10.20.11–13`), not from the laptop. Per-user control lives in the Zero
  Trust policies.
- No `.local`/mDNS discovery and no DHCP address over the tunnel; use names in
  `lan.buunk.org` or IPs.
- Connections from the site back to the laptop are not possible with a tunnel;
  that needs Cloudflare Mesh (only add it if ever needed).
- At home without Cloudflare: a mgmt switch port or the OPNsense console.
