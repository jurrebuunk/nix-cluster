# Opt-in safety net for a risky first network boot. Normally inert.
# Before reboot: record /run/current-system in before/current-system and create
# /var/lib/n5-rollout/pending (root-only). Disarm after verifying a new SSH login.
# Recovery also requires restoring this host's switch port to native VLAN 10.
{ config, pkgs, ... }:
let
  state = "/var/lib/n5-rollout";
in
{
  systemd.timers.n5-rollback = {
    description = "Rollback an unconfirmed network rollout after ten minutes";
    wantedBy = [ "timers.target" ];
    unitConfig.ConditionPathExists = "${state}/pending";
    timerConfig = {
      OnBootSec = "10min";
      AccuracySec = "1s";
      Unit = "n5-rollback.service";
    };
  };

  systemd.services.n5-rollback = {
    description = "Restore the pre-rollout boot generation and reboot";
    unitConfig.ConditionPathExists = "${state}/pending";
    serviceConfig.Type = "oneshot";
    path = [ config.nix.package pkgs.systemd pkgs.coreutils ];
    script = ''
      set -eu
      old=$(head -n 1 ${state}/before/current-system)
      case "$old" in
        /nix/store/*-nixos-system-*) ;;
        *) echo "Invalid saved system path" >&2; exit 1 ;;
      esac
      test -x "$old/bin/switch-to-configuration"
      echo "Network rollout not confirmed; restoring $old"
      nix-env --profile /nix/var/nix/profiles/system --set "$old"
      "$old/bin/switch-to-configuration" boot
      mv ${state}/pending ${state}/rolled-back
      systemctl reboot
    '';
  };
}
