{
  description = "NixOS configs for the hgd1 hypervisors";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Platform API and CLI; always a release tag (docs/concepts/api.md).
    clusterd = {
      url = "github:jurrebuunk/clusterd/v1.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, agenix, microvm, clusterd, ... }:
    let
      system = "x86_64-linux";
      inventory = import ./inventory.nix;
      pkgs = nixpkgs.legacyPackages.${system};
      guestConfigurations = builtins.mapAttrs (vmName: vm:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inventory vmName vm; };
          modules = [ microvm.nixosModules.microvm ./modules/microvm/guest ];
        }) inventory.vms;
    in
    {
      nixosConfigurations = (builtins.mapAttrs (host: _:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inventory guestConfigurations; };
          modules = [
            agenix.nixosModules.default
            microvm.nixosModules.host
            ./hosts/common.nix
            ./modules/network.nix
            ./modules/microvm/host
            ./modules/rollout-safety.nix
            ./modules/ceph.nix
            ./modules/s3-ha
            ./modules/remote-access.nix
            ./modules/monitoring
            clusterd.nixosModules.clusterd
            ./modules/clusterd
            (./hosts + "/${host}")
            # The commit a host was built from; clusterd reports it, so
            # `labctl host list` shows whether every host runs the same one.
            { system.configurationRevision = self.rev or self.dirtyRev or null; }
          ];
        }) inventory.hosts) // guestConfigurations;

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          agenix.packages.${system}.default
          pkgs.cloudflared
          pkgs.jq
          pkgs.kubectl
          clusterd.packages.${system}.labctl
          pkgs.nmap
          pkgs.nixos-rebuild-ng
          pkgs.shellcheck
          pkgs.zensical
        ]
        # Short names for scripts/*.sh that work from anywhere in the repo,
        # also with `nix develop -c`: deploy, kubeconfig, ceph-bootstrap.
        ++ map (name: pkgs.writeShellScriptBin name ''
          exec "$(git rev-parse --show-toplevel)/scripts/${name}.sh" "$@"
        '') [ "deploy" "kubeconfig" "ceph-bootstrap" ];
        # Written by scripts/kubeconfig.sh.
        shellHook = ''
          export KUBECONFIG="''${KUBECONFIG:-$HOME/.kube/hgd1.yaml}"
        '';
      };
    };
}
