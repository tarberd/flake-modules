{
  mkFlakeModule,
  nixpkgs,
  ...
}:
let
  system = "x86_64-linux";
  pkgs = nixpkgs.legacyPackages.${system};
in
mkFlakeModule { } {
  ${system}.default = pkgs.hello;
}
