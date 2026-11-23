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
}
