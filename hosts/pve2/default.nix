{ ... }:
{
  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "pve2";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  systemd.tmpfiles.rules = [ "d /srv/volumes 0755 root root -" ];
}
