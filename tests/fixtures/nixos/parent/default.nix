{ mkFlakeModule, ... }:
mkFlakeModule.withNixosModule { public = [ ./child.nix ]; } (
  { lib, ... }:
  {
    options.parentOption = lib.mkOption {
      type = lib.types.str;
      default = "parent";
    };
  }
)
