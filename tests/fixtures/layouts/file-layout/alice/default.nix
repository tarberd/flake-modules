{ mkFlakeModule, ... }: mkFlakeModule { public = [ ./bob.nix ]; } { name = "alice"; }
