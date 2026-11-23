# Each host independently issues and renews its own DNS-01 certificate.
{ config, lib, inventory, ... }:
let
  cfg = inventory.ceph.s3;
in
lib.mkIf cfg.enable {
  age.secrets.s3-acme-cloudflare.file = ../../secrets/s3-acme-cloudflare.age;

  # No public A record or Internet-facing HTTP listener is required.
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
}
