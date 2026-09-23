{
  description = "A flake powered by flake-modules";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-modules.url = "github:tarberd/flake-modules";
  };

  outputs = inputs@{ flake-modules, ... }:
    flake-modules.lib.evalFlake ./flake-modules.nix inputs;
}
