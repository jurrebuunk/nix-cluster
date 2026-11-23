# Install guest runners without restarting running VMs; restart is explicit.
{ config, lib, inventory, guestConfigurations, ... }:
let
  name = config.networking.hostName;
  host = inventory.hosts.${name};
  enabled = lib.filterAttrs (_: vm: vm.enabled && vm.host == name) inventory.vms;
in
{
  imports = [
    ./validation.nix
    ./networking.nix
    ./k3s-secrets.nix
  ];

  # hv02's firmware hides VMX: avoid a failed modules-load unit there.
  boot.kernelModules = lib.optionals host.kvmAvailable [ "kvm_intel" ];
  hardware.ksm.enable = false;

  # Root-managed TAPs only; never expose bridges via qemu-bridge-helper.
  environment.etc."qemu/bridge.conf".text = "deny all\n";

  microvm = {
    stateDir = "/var/lib/microvms";
    vms = lib.mapAttrs (vmName: _: {
      evaluatedConfig = guestConfigurations.${vmName};
      autostart = true;
      restartIfChanged = false;
    }) enabled;
  };

  # Wait for bridges, not TAPs: the VM service creates its own TAP interfaces.
  systemd.services = lib.mapAttrs' (
    vmName: _:
    lib.nameValuePair "microvm@${vmName}" {
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      unitConfig.ConditionPathExists = "/dev/kvm";
    }
  ) enabled;
}
