# api.lan.buunk.org follows a host whose clusterd answers /v1/health over TLS
# with the real certificate.
{ config, lib, pkgs, inventory, ... }:
let
  cfg = inventory.api;
  hostName = config.networking.hostName;
  host = inventory.hosts.${hostName};
  peers = lib.filter (ip: ip != host.ip.infra) (map (h: h.ip.infra) (lib.attrValues inventory.hosts));

  checkApi = pkgs.writeShellScript "check-clusterd" ''
    exec ${pkgs.curl}/bin/curl \
      --silent --show-error --fail --max-time 1 --noproxy '*' \
      --cacert ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
      --resolve ${cfg.hostname}:443:${host.ip.infra} \
      https://${cfg.hostname}/v1/health >/dev/null 2>&1
  '';
in
{
  # The VIP listener is bound before this host owns the address.
  # Also set by modules/s3-ha when S3 is enabled.
  boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = lib.mkDefault 1;

  users.groups.keepalived_script = { };
  users.users.keepalived_script = {
    isSystemUser = true;
    group = "keepalived_script";
  };

  services.keepalived = {
    enable = true;
    enableScriptSecurity = true;
    openFirewall = false;
    vrrpScripts.clusterd = {
      script = "${checkApi}";
      user = "keepalived_script";
      interval = 2;
      timeout = 2;
      fall = 2;
      rise = 2;
      weight = 0;
    };
    vrrpInstances.api = {
      interface = host.interface;
      state = "BACKUP";
      virtualRouterId = cfg.virtualRouterId;
      priority = 150 - 10 * lib.lists.findFirstIndex (name: name == hostName) 0 (lib.attrNames inventory.hosts);
      noPreempt = true;
      unicastSrcIp = host.ip.infra;
      unicastPeers = peers;
      virtualIps = [
        {
          addr = "${cfg.virtualIP}/32";
          dev = host.interface;
          label = "${host.interface}:api";
        }
      ];
      trackScripts = [ "clusterd" ];
      extraConfig = ''
        version 3
        advert_int 1
        check_unicast_src
        unicast_fault_no_peer
        garp_master_delay 0
        garp_master_repeat 3
      '';
    };
  };
}
