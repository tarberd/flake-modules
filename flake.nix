{
  description = "A declarative, Rust-inspired monadic module system for Nix flakes";

  inputs = {};

  outputs = { self }: {
    lib = import ./lib;

    templates.default = {
      path = ./template;
      description = "A starter flake using the flake-modules system";
    };
  };
}
