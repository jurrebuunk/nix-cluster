# HTTPS on the management NIC only: the laptop over WARP, peers' /v1/status
# fan-out, and the web UI through one OPNsense rule. VRRP from the peers is
# already allowed by modules/monitoring/firewall.nix (same NIC, same peers).
{ config, inventory, ... }:
let
  host = inventory.hosts.${config.networking.hostName};
in
{
  networking.firewall.interfaces.${host.interface}.allowedTCPPorts = [ 443 ];
}
