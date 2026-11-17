# Remote admin access through Cloudflare Zero Trust (network/PLAN.md, step N7).
# Every host runs the same tunnel, so any one host keeps access up. The tunnel
# only connects outwards; nothing in the cluster depends on it.
#
# Off until inventory.remoteAccess.tunnelId is set and
# secrets/cloudflared-tunnel.age exists (see network/REMOTE-ACCESS.md).
{ lib, inventory, ... }:
let
  cfg = inventory.remoteAccess;
in
lib.mkIf (cfg.tunnelId != null) {
  age.secrets.cloudflared-tunnel.file = ../secrets/cloudflared-tunnel.age;

  services.cloudflared = {
    enable = true;
    tunnels.${cfg.tunnelId} = {
      credentialsFile = "/run/agenix/cloudflared-tunnel";
      # Route WARP clients into the private networks announced for this tunnel.
      warp-routing.enabled = true;
      default = "http_status:404";
    };
  };

  # Lets cloudflared (a dynamic user) proxy ping from WARP clients.
  boot.kernel.sysctl."net.ipv4.ping_group_range" = "0 2147483647";
}
