# Pure network identities shared by microVM host and guest modules.
{ lib }:
{
  networkFor =
    vm:
    let
      octet = lib.toLower (lib.fixedWidthString 2 "0" (lib.toHexString vm.id));
    in
    {
      k8s = {
        tap = "tap${toString vm.id}-k8s";
        mac = "02:00:00:40:00:${octet}";
      };
      storage = {
        tap = "tap${toString vm.id}-stor";
        mac = "02:00:00:30:00:${octet}";
      };
    };
}
