{
  mkFlakeModule,
  self,
  super,
  flake,
  ...
}:
mkFlakeModule { } {
  privateVal = "private";
  canSeePublic = flake.publicChild.publicVal;
  rootIsSuper = super.rootVal;
  hasOwnSelf = self ? privateVal;
}
