{ mkFlakeModule, self, ... }:
mkFlakeModule { private = [ ./bob/charlie.nix ]; } {
  name = "bob";
  charlieView = self.charlie;
}
