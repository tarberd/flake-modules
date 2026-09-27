{ mkFlakeModule, ... }:
mkFlakeModule.withNixosModule { } (
  { lib, ... }:
  {
    options.leafOption = lib.mkOption {
      type = lib.types.str;
      default = "leaf";
    };
  }
)
