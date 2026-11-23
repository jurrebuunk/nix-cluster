# VIP ownership follows local proxy/TLS readiness, never Ceph health.
{ config, lib, pkgs, inventory, ... }:
let
  cfg = inventory.ceph.s3;
  hostName = config.networking.hostName;
  host = inventory.hosts.${hostName};
  hostNames = lib.attrNames inventory.hosts;
  peers = lib.filter (ip: ip != host.ip.storage) (
    map (peer: peer.ip.storage) (lib.attrValues inventory.hosts)
  );

  # Verify the running proxy's loaded, publicly trusted certificate. A local
  # RGW outage or degraded Ceph cluster must not withdraw a usable proxy VIP.
  checkProxy = pkgs.writeShellScript "check-s3-proxy" ''
    exec ${pkgs.curl}/bin/curl \
      --silent --show-error --fail --max-time 1 --noproxy '*' \
      --cacert ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
      --resolve ${cfg.hostname}:9443:127.0.0.1 \
      https://${cfg.hostname}:9443/ >/dev/null 2>&1
  '';
in
lib.mkIf cfg.enable {
  # Standbys bind the VIP before acquiring it; no routes/forwarding are added.
  boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = 1;

  users.groups.keepalived_script = { };
  users.users.keepalived_script = {
    isSystemUser = true;
    group = "keepalived_script";
  };

  services.keepalived = {
    enable = true;
    enableScriptSecurity = true;
    # firewall.nix owns the narrow rules, not the module's broad VRRP/AH opening.
    openFirewall = false;
    vrrpScripts.s3_proxy = {
      script = "${checkProxy}";
      user = "keepalived_script";
      interval = 2;
      timeout = 2;
      fall = 2;
      rise = 2;
      weight = 0;
    };
    vrrpInstances.s3 = {
      interface = "br-stor";
      state = "BACKUP";
      virtualRouterId = cfg.virtualRouterId;
      priority = 150 - 10 * lib.lists.findFirstIndex (name: name == hostName) 0 hostNames;
      noPreempt = true;
      unicastSrcIp = host.ip.storage;
      unicastPeers = peers;
      virtualIps = [
        {
          addr = "${cfg.virtualIP}/32";
          dev = "br-stor";
          label = "br-stor:s3";
        }
      ];
      trackScripts = [ "s3_proxy" ];
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

  systemd.services.keepalived = {
    after = [ "haproxy.service" ];
    wants = [ "haproxy.service" ];
  };
}
