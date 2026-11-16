{ ... }:
{
  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "pve1";

  # Bootloader configuration will be added during this host's installation.
}
