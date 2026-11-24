# agenix recipients. Encrypt with: cd secrets && agenix -e <name>.age
let
  inventory = import ../inventory.nix;
  hosts = map (h: h.hostKey) (builtins.attrValues inventory.hosts);
  all = inventory.adminKeys ++ hosts;
in
{
  "cloudflared-tunnel.age".publicKeys = all;
  "s3-acme-cloudflare.age".publicKeys = all;
  # Hosts share these read-only into their VMs (modules/microvm/host/k3s-secrets.nix).
  "k3s-server-token.age".publicKeys = all;
  "k3s-agent-token.age".publicKeys = all;
  # snmp_exporter auth file (auths.hgd1.community: the switch's read-only community).
  "snmp-community.age".publicKeys = all;
  # clusterd (modules/clusterd/): token hashes ("<name> <scope> sha256:<hex>"
  # lines from `labctl token new`), its ServiceAccount kubeconfig and its
  # read-only Ceph keyring (client.clusterd, mon 'allow r').
  "api-tokens.age".publicKeys = all;
  "clusterd-kubeconfig.age".publicKeys = all;
  "clusterd-ceph-keyring.age".publicKeys = all;
  # RGW user `clusterd` (caps buckets/users/usage/metadata=read, no buckets of
  # its own): {"access_key": …, "secret_key": …} for the admin API.
  "clusterd-s3-admin.age".publicKeys = all;
  # Backup of the age key Flux decrypts hgd1-k8s secrets with (the cluster
  # holds it as Secret flux-system/sops-age). Never deployed: admins only.
  "flux-sops-age.age".publicKeys = inventory.adminKeys;
}
