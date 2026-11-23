# Private S3 endpoint, independent of k3s: HAProxy on every host, one VRRP VIP.
{
  config,
  lib,
  pkgs,
  inventory,
  ...
}:
let
  cfg = inventory.ceph.s3;
  hostName = config.networking.hostName;
  host = inventory.hosts.${hostName};
  hostNames = lib.attrNames inventory.hosts;
  hosts = lib.attrValues inventory.hosts;
  peers = lib.filter (ip: ip != host.ip.storage) (map (h: h.ip.storage) hosts);
  assignedStorageIPs =
    map (h: h.ip.storage) hosts ++ map (vm: vm.ip.storage) (lib.attrValues inventory.vms);
  certificate = "/var/lib/acme/${cfg.hostname}/full.pem";

  # Check the running proxy's loaded, publicly trusted certificate and local
  # listener. This must NOT depend on the local RGW or Ceph being HEALTH_OK:
  # one failed storage host is an expected, usable degraded state.
  checkProxy = pkgs.writeShellScript "check-s3-proxy" ''
    exec ${pkgs.curl}/bin/curl \
      --silent --show-error --fail --max-time 1 --noproxy '*' \
      --cacert ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
      --resolve ${cfg.hostname}:9443:127.0.0.1 \
      https://${cfg.hostname}:9443/ >/dev/null 2>&1
  '';

  backendServers = lib.concatMapStringsSep "\n" (
    name: "server ${name} ${inventory.hosts.${name}.ip.storage}:7480 check inter 2s fall 3 rise 2"
  ) hostNames;

  vrrpRules = lib.concatMapStringsSep "\n" (peer: ''
    iptables -C nixos-fw -i br-stor -s ${peer} -d ${host.ip.storage} -p vrrp -m ttl --ttl-eq 255 -j ACCEPT 2>/dev/null || \
      iptables -A nixos-fw -i br-stor -s ${peer} -d ${host.ip.storage} -p vrrp -m ttl --ttl-eq 255 -j ACCEPT
  '') peers;
  removeVrrpRules = lib.concatMapStringsSep "\n" (peer: ''
    iptables -D nixos-fw -i br-stor -s ${peer} -d ${host.ip.storage} -p vrrp -m ttl --ttl-eq 255 -j ACCEPT 2>/dev/null || true
  '') peers;
in
lib.mkIf cfg.enable {
  assertions = [
    {
      assertion = lib.length hosts >= 2 && !lib.elem cfg.virtualIP assignedStorageIPs;
      message = "S3 HA needs multiple hosts and a VIP distinct from all host/guest storage addresses";
    }
    {
      assertion =
        lib.hasPrefix "10.10.30." cfg.virtualIP
        && !lib.elem cfg.virtualIP [
          "10.10.30.0"
          "10.10.30.255"
        ];
      message = "S3 VIP must be a usable address on the unrouted storage VLAN";
    }
  ];

  # HAProxy must bind the VIP on standbys before they acquire it. This does
  # not add a route, expose management ports, or enable IP forwarding.
  boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = 1;

  age.secrets.s3-acme-cloudflare.file = ../secrets/s3-acme-cloudflare.age;

  # Each node has its own certificate/account state and renews independently.
  # DNS-01 works without a public A record or an Internet-facing HTTP listener.
  security.acme = {
    acceptTerms = true;
    certs.${cfg.hostname} = {
      email = cfg.acmeEmail;
      server = cfg.acmeServer;
      dnsProvider = "cloudflare";
      dnsResolver = "1.1.1.1:53";
      credentialFiles.CF_DNS_API_TOKEN_FILE = config.age.secrets.s3-acme-cloudflare.path;
      group = "haproxy";
      reloadServices = [ "haproxy.service" ];
      enableDebugLogs = false;
    };
  };

  services.haproxy = {
    enable = true;
    config = ''
      global
        log stdout format raw local0
        maxconn 1024
        nbthread 2
        ssl-default-bind-options ssl-min-ver TLSv1.2

      defaults
        mode http
        log global
        # Never log S3 object paths or bearer-style presigned query strings.
        log-format "%ci:%cp [%tr] %ft %b/%s %ST %B %Tt"
        timeout connect 5s
        timeout client 15m
        timeout server 15m
        timeout http-request 30s
        timeout http-keep-alive 30s
        timeout check 3s
        retries 2

      frontend s3_https
        bind ${cfg.virtualIP}:443 ssl crt ${certificate} alpn h2,http/1.1
        default_backend rgw

      # Loopback only: verify local TLS readiness without relying on RGW.
      frontend local_tls_health
        bind 127.0.0.1:9443 ssl crt ${certificate} alpn http/1.1
        http-request return status 200 content-type text/plain string ready

      backend rgw
        balance leastconn
        option httpchk
        http-check send meth GET uri / ver HTTP/1.1 hdr Host ${cfg.hostname} hdr Connection close
        http-check expect rstatus ^(200|403)$
        # Do not rewrite Host, URI or query parameters: S3 SigV4 signs them.
        ${backendServers}
    '';
  };

  systemd.services.haproxy = {
    # Config/certificate updates should drain old workers, not cut uploads.
    reloadIfChanged = true;
    requires = [ "acme-${cfg.hostname}.service" ];
    after = [
      "acme-${cfg.hostname}.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    serviceConfig.LimitNOFILE = 8192;
  };

  users.groups.keepalived_script = { };
  users.users.keepalived_script = {
    isSystemUser = true;
    group = "keepalived_script";
  };

  services.keepalived = {
    enable = true;
    enableScriptSecurity = true;
    # The module's broad VRRP/AH firewall opening is intentionally not used.
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

  # TLS is only available to storage peers. VRRP is IPv4, storage-interface
  # scoped, exact-peer scoped and one hop only. No router storage route added.
  networking.firewall = {
    interfaces.br-stor.allowedTCPPorts = [ 443 ];
    extraCommands = vrrpRules;
    extraStopCommands = removeVrrpRules;
  };
}
