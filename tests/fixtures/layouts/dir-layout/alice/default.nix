{ mkFlakeModule, ... }: mkFlakeModule { public = [ ./bob ]; } { name = "alice"; }
