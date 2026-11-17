# Remote access through Cloudflare (network plan N7)

Reach the whole site network (`10.10.0.0/16`) from anywhere, as if on the LAN:
SSH, OPNsense and switch web UIs, the k8s API, internal apps and internal names.
`cloudflared` runs on all three hypervisors (one tunnel, three replicas); the
laptop uses the Cloudflare One (WARP) client. Nothing in the cluster depends on
this path.

Config: [`modules/remote-access.nix`](../modules/remote-access.nix), switched on
by `remoteAccess.tunnelId` in [`inventory.nix`](../inventory.nix). Do this after
network plan N4–N6, with the hosts on `10.10.20.11–13`.

## 1. Zero Trust organisation (dashboard, once)

- [ ] Cloudflare dashboard → Zero Trust: create the organisation (team name)
      on the **Free** plan. Cloudflare may ask for a payment method even on
      Free.
- [ ] Settings → Authentication: keep **One-time PIN** (or add GitHub/Google).
- [ ] Settings → WARP Client → Device enrollment permissions: a rule that only
      allows **your email address**.

## 2. Tunnel (laptop, in this repo)

```sh
nix develop
cloudflared tunnel login                     # browser; pick the buunk.org zone
cloudflared tunnel create hgd1-admin         # prints the tunnel UUID
cloudflared tunnel route ip add 10.10.0.0/16 hgd1-admin
```

`create` writes the credentials to `~/.cloudflared/<UUID>.json`.

- [ ] Put the UUID in `inventory.nix`: `remoteAccess.tunnelId = "<UUID>";`
- [ ] Encrypt the credentials for the laptop and all three hosts:
      ```sh
      cd secrets
      EDITOR="cp $HOME/.cloudflared/<UUID>.json" agenix -e cloudflared-tunnel.age
      cd ..
      ```
- [ ] Keep a copy of the JSON in your password manager, then delete
      `~/.cloudflared/<UUID>.json`.
- [ ] Commit, then deploy one host at a time:
      ```sh
      scripts/deploy.sh hgd1-hv01 switch
      ssh jurre@10.10.20.11 'systemctl status "cloudflared-tunnel-*" --no-pager'
      ```
      Repeat for `hgd1-hv02` and `hgd1-hv03`. The dashboard (Networks →
      Tunnels → hgd1-admin) shows 3 connectors.

## 3. WARP client settings (dashboard)

- [ ] Settings → WARP Client → Device settings → Default profile → **Split
      Tunnels** (Exclude mode): replace the entry `10.0.0.0/8` by these
      ranges, which are all of `10.0.0.0/8` except `10.10.0.0/16`:
      ```
      10.0.0.0/13
      10.8.0.0/15
      10.11.0.0/16
      10.12.0.0/14
      10.16.0.0/12
      10.32.0.0/11
      10.64.0.0/10
      10.128.0.0/9
      ```
      (Removing `10.0.0.0/8` entirely would also send other `10.x` networks,
      e.g. at school, into the tunnel.)
- [ ] Same profile → **Local Domain Fallback**: add `hgd1.lan.buunk.org` with
      DNS server `10.10.20.1` (OPNsense).
- [ ] Gateway → Firewall policies → Network: allow destination
      `10.10.0.0/16` for your email; block `10.10.0.0/16` for everyone else.

## 4. OPNsense

- [ ] Firewall → Rules → INFRA: allow source `10.10.20.11–13` to MGMT, K8S and
      USERS (everything internal except storage, which is not routed).
- [ ] Once remote access works: remove the temporary WAN rules (22/443 from
      `192.168.2.0/24`, SSH to `10.10.0.0/16`) and tick "Block private
      networks" on WAN again (network plan N7).

## 5. Laptop

- [ ] Install the WARP client. On NixOS: `services.cloudflare-warp.enable = true;`
      in the laptop config, then `warp-cli registration new <team-name>` and
      `warp-cli connect`. On other systems: the Cloudflare One app.

## Verify (from outside the home network, e.g. a phone hotspot)

```sh
warp-cli status                                   # Connected
ssh jurre@10.10.20.11 hostname                    # hgd1-hv01
getent hosts hgd1-hv02.hgd1.lan.buunk.org         # 10.10.20.12
curl -kI https://10.10.10.1                       # OPNsense web UI
```

Then power off (or stop `cloudflared` on) one hypervisor and repeat: access must
keep working through the other two.

## Notes

- Internal servers see remote traffic coming from a hypervisor
  (`10.10.20.11–13`), not from the laptop. Per-user control lives in the Zero
  Trust policies.
- No `.local`/mDNS discovery and no DHCP address over the tunnel; use names in
  `hgd1.lan.buunk.org` or IPs.
- Connections from the site back to the laptop are not possible with a tunnel;
  that needs Cloudflare Mesh (only add it if ever needed).
- At home without Cloudflare: a mgmt switch port or the OPNsense console.
