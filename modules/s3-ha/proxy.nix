# TLS termination and S3-safe balancing across the shared RGW object store.
{ lib, inventory, ... }:
let
  cfg = inventory.ceph.s3;
  certificate = "/var/lib/acme/${cfg.hostname}/full.pem";
  backendServers = lib.concatMapStringsSep "\n" (
    name: "server ${name} ${inventory.hosts.${name}.ip.storage}:7480 check inter 2s fall 3 rise 2"
  ) (lib.attrNames inventory.hosts);
in
lib.mkIf cfg.enable {
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

      # Loopback only: metrics for the monitoring (modules/monitoring/).
      frontend metrics
        bind 127.0.0.1:8405
        no log
        http-request use-service prometheus-exporter if { path /metrics }
        http-request return status 404

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
    # Config/certificate updates drain old workers rather than cut uploads.
    reloadIfChanged = true;
    requires = [ "acme-${cfg.hostname}.service" ];
    after = [
      "acme-${cfg.hostname}.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    serviceConfig.LimitNOFILE = 8192;
  };
}
