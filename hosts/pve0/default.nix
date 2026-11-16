{ ... }:
{
  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "pve0";

  # Bootloader configuration will be added during this host's installation.
}
