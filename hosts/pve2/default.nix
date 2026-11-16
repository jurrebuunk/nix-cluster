{ ... }:
{
  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "pve2";

  # Bootloader configuration will be added during this host's installation.
}
