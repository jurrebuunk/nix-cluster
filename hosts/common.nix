{ config, lib, inventory, ... }:
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  boot.loader.systemd-boot.configurationLimit = 20;

  # Ceph mons need closely synced clocks: OPNsense first, public pool as fallback.
  services.chrony = {
    enable = true;
    servers = config.networking.timeServers;
    # Listing a server first does not make chrony prefer it. Keep public pool
    # servers as fallbacks, but explicitly prefer the site's clock.
    extraConfig = lib.concatMapStringsSep "\n"
      (server: "server ${server} iburst prefer") inventory.ntp;
  };

  services.journald.extraConfig = ''
    SystemMaxUse=1G
    MaxRetentionSec=30day
  '';
  services.fstrim.enable = true;

  # Advertise <hostname>.local for headless discovery on the local network.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  services.openssh = {
    enable = true;
    # Management NIC only; guest-facing/storage bridges are not SSH entrypoints.
    openFirewall = false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  users.users.jurre = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = inventory.adminKeys;
  };
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "26.05";
}
