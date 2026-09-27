{ mkFlakeModule, self, ... }:
mkFlakeModule
  {
    public = [ ./publicChild.nix ];
    private = [ ./privateChild.nix ];
  }
  {
    rootVal = "root";
    privateView = self.privateChild;
  }
