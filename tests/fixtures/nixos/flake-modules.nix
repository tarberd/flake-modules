{ mkFlakeModule, ... }:
mkFlakeModule {
  public = [
    ./leaf.nix
    ./parent
  ];
} { }
