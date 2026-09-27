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
      # `nix fmt` from this directory formats the whole repository: nixfmt-tree
      # walks the enclosing git repository. The root flake has no inputs, so the
      # formatter lives here.
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

      # Exposed for 'nix flake check'
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          nixUnitBin = nix-unit.packages.${system}.default;
        in
        {
          unit-tests =
            pkgs.runCommand "flake-modules-unit-tests"
              {
                nativeBuildInputs = [ nixUnitBin ];
              }
              ''
                export HOME=$PWD
                nix-unit --eval-store "$PWD" ${./.}/test_lib.nix \
                  --arg lib "import ${flake-modules}/lib" \
                  --arg internal "import ${flake-modules}/lib/internal.nix" \
                  --arg pkgs "import ${nixpkgs} { system = \"${system}\"; }" \
                  --arg templatePath "${flake-modules}/template"
                touch $out
              '';

          # Fails when any .nix file in the repository is not nixfmt-formatted;
          # run `nix fmt` from this directory to fix
          formatting =
            pkgs.runCommand "flake-modules-formatting"
              {
                nativeBuildInputs = [ pkgs.nixfmt ];
              }
              ''
                find ${flake-modules} -type f -name '*.nix' -print0 | xargs -0 -r nixfmt --check
                touch $out
              '';
        }
      );
    };
}
