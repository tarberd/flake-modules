{ createFlakeModule, self, super, flake, ... }:
createFlakeModule {
  privateVal = "private";
  canSeePublic = flake.publicChild.publicVal;
  rootIsSuper = super.rootVal;
  hasOwnSelf = self ? privateVal;
}
