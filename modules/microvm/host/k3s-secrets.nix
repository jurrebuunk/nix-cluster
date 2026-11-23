# Decrypt k3s tokens into one directory per VM role; guests mount it read-only
# over virtiofs. Agents never see the server token.
{ config, lib, inventory, ... }:
let
  name = config.networking.hostName;
  enabled = lib.filterAttrs (_: vm: vm.enabled && vm.host == name) inventory.vms;
  roles = lib.unique (map (vm: vm.role) (builtins.attrValues enabled));
  k3s = import ../../../lib/k3s.nix { inherit inventory; };
  # Plain files, not symlinks into /run/agenix: those would dangle in the guest.
  token = role: kind: {
    file = ../../../secrets/k3s-${kind}-token.age;
    path = "${k3s.hostSecretDir role}/${kind}-token";
    symlink = false;
  };
in
{
  age.secrets =
    lib.optionalAttrs (lib.elem "server" roles) {
      k3s-server-token = token "server" "server";
      k3s-server-agent-token = token "server" "agent";
    }
    // lib.optionalAttrs (lib.elem "agent" roles) {
      k3s-agent-token = token "agent" "agent";
    };
}
