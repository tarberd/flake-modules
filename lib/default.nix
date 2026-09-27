# Public API of flake-modules. The implementation lives in ./internal.nix,
# which the test suite imports directly for white-box tests.
let
  internal = import ./internal.nix;
in
{
  inherit (internal) evalFlake mkFlake;
}
