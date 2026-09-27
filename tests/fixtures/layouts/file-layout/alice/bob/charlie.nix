{
  mkFlakeModule,
  self,
  super,
  flake,
  ...
}:
mkFlakeModule { } {
  name = "charlie";
  selfName = self.name;
  superName = super.name;
  aliceName = flake.alice.name;
  rootMarker = flake.rootMarker;
}
