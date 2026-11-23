# Publicly trusted certificate for api.lan.buunk.org through DNS-01, like the
# S3 endpoint. clusterd reloads it on SIGHUP, without dropping connections.
{ config, inventory, ... }:
let
  cfg = inventory.api;
in
{
  age.secrets.s3-acme-cloudflare.file = ../../secrets/s3-acme-cloudflare.age;

  security.acme = {
    acceptTerms = true;
    certs.${cfg.hostname} = {
      email = inventory.ceph.s3.acmeEmail;
      server = inventory.ceph.s3.acmeServer;
      dnsProvider = "cloudflare";
      dnsResolver = "1.1.1.1:53";
      credentialFiles.CF_DNS_API_TOKEN_FILE = config.age.secrets.s3-acme-cloudflare.path;
      group = "clusterd";
      reloadServices = [ "clusterd.service" ];
      enableDebugLogs = false;
    };
  };
}
