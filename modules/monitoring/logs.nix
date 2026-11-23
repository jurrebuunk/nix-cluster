# Vector ships this host's journal and the router/switch syslog (sent to the
# VIP) to every host's VictoriaLogs.
{ lib, inventory, ... }:
let
  cfg = inventory.monitoring;
  logs = import ../../lib/logs.nix { inherit lib; };
  urls = map (h: "http://${h.ip.infra}:9428") (lib.attrValues inventory.hosts);
in
{
  services.vector = {
    enable = true;
    journaldAccess = true;
    settings = {
      data_dir = "/var/lib/vector";
      sources = {
        journald.type = "journald";
        syslog_udp = {
          type = "syslog";
          mode = "udp";
          address = "0.0.0.0:514";
        };
        syslog_tcp = {
          type = "syslog";
          mode = "tcp";
          address = "0.0.0.0:514";
        };
        internal_metrics.type = "internal_metrics";
      };
      transforms.normalized = logs.normalize inventory.site.domain {
        ${cfg.router.ip} = cfg.router.name;
        ${cfg.switch.ip} = cfg.switch.name;
      } [
        "journald"
        "syslog_udp"
        "syslog_tcp"
      ];
      sinks = logs.sinks "normalized" urls // {
        metrics = {
          type = "prometheus_exporter";
          inputs = [ "internal_metrics" ];
          address = "127.0.0.1:9598";
        };
      };
    };
  };
}
