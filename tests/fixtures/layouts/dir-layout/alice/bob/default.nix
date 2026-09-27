{ mkFlakeModule, self, ... }:
mkFlakeModule { private = [ ./charlie.nix ]; } {
  name = "bob";
  charlieView = self.charlie;
}
