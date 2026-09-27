args@{ mkFlakeModule, self, ... }:
mkFlakeModule { } {
  argNames = builtins.attrNames args;
  selfIsModuleScope = self ? argNames;
}
