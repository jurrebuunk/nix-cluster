# The owning host scrapes node_exporter over the storage NIC, and Vector ships
# the journal to every host's VictoriaLogs; neither goes through the router.
{ lib, inventory, ... }:
let
  logs = import ../../../lib/logs.nix { inherit lib; };
  urls = map (h: "http://${h.ip.storage}:9428") (lib.attrValues inventory.hosts);
in
{
  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [ "systemd" ];
  };
  networking.firewall.interfaces.storage.allowedTCPPorts = [ 9100 ];

  services.vector = {
    enable = true;
    journaldAccess = true;
    settings = {
      data_dir = "/var/lib/vector";
      sources.journald.type = "journald";
      transforms.normalized = logs.normalize [ "journald" ];
      sinks = logs.sinks "normalized" urls;
    };
  };
}
