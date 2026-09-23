# flake-modules

A declarative, Rust-inspired monadic module system for Nix flakes.

`flake-modules` provides a structured, hierarchical approach to organizing complex Nix flakes using explicit module declarations, public/private scoping, and intuitive relative/absolute navigation (`self`, `super`, `flake`).

---

## Why `flake-modules`?

Most modular flake solutions (like `flake-parts`) use a flat, attribute-merging model where all options and submodules live in a single global namespace. While great for small-to-medium flakes, large monorepos suffer from:
- **Lack of Encapsulation**: Private helper files and internal implementation details leak into the top-level flake schema.
- **Accidental Namespace Collisions**: Sibling projects or multi-host definitions can conflict with each other unless artificially namespaced by hand.
- **Ambiguous Provenance**: It is often unclear whether an attribute comes from the current module, a parent directory, or external flake inputs.

`flake-modules` brings **Rust's module hierarchy and scoping semantics** to Nix:

| Concept | Rust Equivalent | In `flake-modules` | Meaning |
| :--- | :--- | :--- | :--- |
| **Current Scope** | `self::` | `self` | Access the current module's content and all of its submodules (both public and private). |
| **Parent Scope** | `super::` | `super` | Access the immediate parent module's `self` scope. |
| **Root Scope** | `crate::` | `flake` | Access the root namespace of the flake (all top-level modules). |
| **Private Submodule** | `mod foo;` | `mod "foo"` | Submodule is evaluated and available to `self` and children, but **hidden** from external consumers. |
| **Public Submodule** | `pub mod foo;` | `pub mod "foo"` | Submodule is evaluated and exported as part of the public API / flake outputs. |
| **External Deps** | `extern crate` | Function Arguments | External flake inputs (`nixpkgs`, `disko`, `home-manager`) passed directly as module arguments. |

---

## Getting Started

### 1. Initialize a New Flake

```bash
nix flake init -t github:tarberd/flake-modules
```

### 2. Manual Setup

Add `flake-modules` to your `flake.nix`:

```nix
{
  description = "My multi-machine flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-modules.url = "github:tarberd/flake-modules";
  };

  outputs = inputs@{ flake-modules, ... }:
    flake-modules.lib.evalFlake ./. inputs;
}
```

Define your root module in `flake-modules.nix`:

```nix
{
  createFlakeModule,
  pub,
  mod,
  ...
}:
# Internal private project modules (accessible across flake via `flake.<name>`)
mod "hosts"
mod "users"

# Public flake outputs exposed to the Nix CLI
pub mod "packages"
pub mod "nixosConfigurations"

createFlakeModule {}
```

---

## Declaring Modules

Every module in the project wraps its content using `createFlakeModule`:

### Leaf Module Example (`packages/onehost.nix`)
```nix
{
  createFlakeModule,
  nixpkgs,
  ...
}:
let
  system = "x86_64-linux";
  pkgs = nixpkgs.legacyPackages.${system};
in
createFlakeModule (pkgs.rustPlatform.buildRustPackage {
  pname = "onehost";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;
})
```

### Parent Module with Re-exports (`packages/default.nix`)
```nix
{
  createFlakeModule,
  mod,
  self,
  ...
}:
# Declare onehost as a private submodule
mod "onehost"

# Re-export it under standard flake output schema
createFlakeModule {
  x86_64-linux.onehost = self.onehost;
}
```

### NixOS Module Deduplication (`declareNixosModule`)
For NixOS modules imported in multiple configurations, wrap the module with `declareNixosModule` inside `createFlakeModule`. This stamps a deterministic `key` (sha256 hash of the canonical file path) so NixOS deduplicates option declarations:

```nix
{
  createFlakeModule,
  declareNixosModule,
  flake,
  ...
}:
createFlakeModule (
  declareNixosModule ({ lib, config, ... }: {
    imports = [
      flake.users.common
    ];

    options.myService.enable = lib.mkEnableOption "my service";
  })
)
```

---

## Core Guarantees & Invariants

1. **Zero External Dependencies**: `flake-modules` is written entirely in pure Nix language primitives. It has an empty `inputs = {};` with zero dependency footprint.
2. **Duplicate Declaration Protection**: Declaring a module twice (`pub mod "foo"` + `pub mod "foo"`, `mod "foo"` + `mod "foo"`, or `pub mod "foo"` + `mod "foo"`) throws an immediate collision error.
3. **Collision Detection**: If a module defines attribute keys in `content` that match declared submodule names, `flake-modules` throws an error to prevent silent attribute clobbering.
4. **Early Validation**: Non-string module names are rejected with clear, actionable type error messages.
5. **Function Lifting**: Functions passed to `createFlakeModule ({ lib, ... }: { ... })` are automatically lifted into callable functors (`__functor`), allowing child submodules to be attached as attributes while the function remains callable as a NixOS/Terranix module.

---

## License

MIT or Apache-2.0
