{
  description = "A flake powered by flake-modules";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-modules.url = "github:tarberd/flake-modules";
  };

  outputs = { self, flake-modules, ... }@inputs:
    flake-modules.lib.mkFlake {
      inherit inputs;
      rootDir = ./.;
      root = { mod, pubMod, createFlakeModule }:
        pubMod "packages"
        createFlakeModule {};
    };
}
