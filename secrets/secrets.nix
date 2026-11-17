# agenix recipients. Encrypt with: cd secrets && agenix -e <name>.age
let
  inventory = import ../inventory.nix;
  hosts = map (h: h.hostKey) (builtins.attrValues inventory.hosts);
  all = inventory.adminKeys ++ hosts;
in
{
  "cloudflared-tunnel.age".publicKeys = all;
}
