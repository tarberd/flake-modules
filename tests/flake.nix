{
  description = "Test harness for flake-modules";

  inputs = {
    flake-modules.url = "path:..";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-unit.url = "github:nix-community/nix-unit";
    nix-unit.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      flake-modules,
      nixpkgs,
      nix-unit,
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      # Exposed for 'nix flake check'
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          nixUnitBin = nix-unit.packages.${system}.default;
        in
        {
          unit-tests = pkgs.runCommand "flake-modules-unit-tests" {
            nativeBuildInputs = [ nixUnitBin ];
          } ''
            export HOME=$PWD
            nix-unit --eval-store "$PWD" ${./.}/test_lib.nix \
              --arg lib "import ${flake-modules}/lib" \
              --arg pkgs "import ${nixpkgs} { system = \"${system}\"; }" \
              --arg templatePath "${flake-modules}/template"
            touch $out
          '';
        }
      );
    };
}
