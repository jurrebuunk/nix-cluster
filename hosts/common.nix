{ ... }:
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  networking.useDHCP = true;

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  users.users.jurre = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDfML1tz4bMJ7uAoIS5Hhd3cTE95X5QdaEJ8hR/1gWnE jurre@b302.nl"
    ];
  };
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "26.05";
}
