{
  createFlakeModule,
  nixpkgs,
  ...
}:
let
  system = "x86_64-linux";
  pkgs = nixpkgs.legacyPackages.${system};
in
createFlakeModule {
  ${system}.default = pkgs.hello;
}
