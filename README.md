# flake-modules

A declarative, Rust-inspired module system for Nix flakes.

`flake-modules` organizes a flake as a tree of modules that mirrors your directory layout. Each module declares its children by path and chooses which of them are public. Modules navigate the tree with `self`, `super` and `flake`, much like Rust's `self::`, `super::` and `crate::`.

---

## Why `flake-modules`?

Most modular flake solutions (like `flake-parts`) use a flat, attribute-merging model where all options and submodules live in a single global namespace. While great for small-to-medium flakes, large monorepos suffer from:
- **Lack of Encapsulation**: Private helper files and internal implementation details leak into the top-level flake schema.
- **Accidental Namespace Collisions**: Sibling projects or multi-host definitions can conflict with each other unless artificially namespaced by hand.
- **Ambiguous Provenance**: It is often unclear whether an attribute comes from the current module, a parent directory, or external flake inputs.

`flake-modules` brings **Rust's module hierarchy and scoping semantics** to Nix:

| Concept | Rust | `flake-modules` | Meaning |
| :--- | :--- | :--- | :--- |
| **Current scope** | `self::` | `self` | The current module's content and all of its children, public and private. |
| **Parent scope** | `super::` | `super` | The parent module's `self`. |
| **Root scope** | `crate::` | `flake` | The root module's `self`: every top-level module, public and private. |
| **Private child** | `mod foo;` | `private = [ ./foo.nix ];` | Visible to its parent (through `self`) and its siblings (through `super`), hidden from everyone else. Top-level private modules are reachable anywhere through `flake`. |
| **Public child** | `pub mod foo;` | `public = [ ./foo.nix ];` | Also visible from outside the parent. At the root, public children are the flake outputs. |
| **Child files** | `foo.rs` + `foo/bar.rs` | `foo.nix` + `foo/bar.nix` | A module's children live in its own directory. |
| **External deps** | Cargo dependencies | Module arguments | Flake inputs (`nixpkgs`, `disko`, `home-manager`) are passed to every module by name. |

---

## Getting Started

### 1. Initialize a New Flake

```bash
nix flake init -t github:tarberd/flake-modules
```

### 2. Manual Setup

Add `flake-modules` to your `flake.nix` and hand the flake over to `evalFlake`:

```nix
{
  description = "My multi-machine flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-modules.url = "github:tarberd/flake-modules";
  };

  outputs = inputs@{ flake-modules, ... }: flake-modules.lib.evalFlake ./. inputs;
}
```

`evalFlake` reads the root module from `flake-modules.nix` next to `flake.nix`:

**`flake-modules.nix`**
```nix
{ mkFlakeModule, ... }:
mkFlakeModule {
  public = [
    ./packages
    ./nixosConfigurations.nix
  ];
  private = [
    ./hosts
    ./users
  ];
} { }
```

The root's public children and its content become the flake outputs, here `packages` and `nixosConfigurations`. The private `hosts` and `users` modules are available inside the flake as `flake.hosts` and `flake.users`, but are not outputs.

The rest of this README builds out this example flake.

---

## Declaring Modules

Every module file is a function of its [module arguments](#module-arguments) that returns `mkFlakeModule` applied to a **declaration** and **content**:

```nix
mkFlakeModule { public = [ /* paths */ ]; private = [ /* paths */ ]; } content
```

The declaration is always passed; `public` and `private` are optional and default to `[ ]`. Entries are paths to the module's children. A module without children is a **leaf**:

```nix
{ mkFlakeModule, ... }: mkFlakeModule { } "hello world"
```

### Content

| Module | Allowed content |
| :--- | :--- |
| Leaf (no children) | Anything: a literal, an attribute set, a function, a derivation, … |
| Parent | An attribute set or a function |

A parent's children are attached to its content as attributes, which is why a parent's content cannot be a literal. Function content is wrapped in a functor, so it stays callable while its children are attached. Content attributes must not share a name with a child.

A parent can re-export a private child under a different shape:

**`packages/default.nix`**
```nix
{ mkFlakeModule, self, ... }:
mkFlakeModule { private = [ ./onehost.nix ]; } {
  x86_64-linux.onehost = self.onehost;
}
```

**`packages/onehost.nix`**
```nix
{ mkFlakeModule, nixpkgs, ... }:
let
  pkgs = nixpkgs.legacyPackages.x86_64-linux;
in
mkFlakeModule { } (pkgs.writeShellScriptBin "onehost" "echo hello from onehost")
```

The flake output is `packages.x86_64-linux.onehost`. Because `onehost` is private, `packages.onehost` itself does not exist outside the `packages` module.

### Module Layout

A module's children live in its **children directory**:

| Module file | Children directory |
| :--- | :--- |
| Root `flake-modules.nix` | The root directory |
| `x/default.nix` | `x/` |
| `x.nix` | `x/` |

A child is declared as `./name.nix` (a file module) or `./name` (a directory containing `default.nix`); either way its name is `name`. The example flake looks like this:

```
.
├── flake.nix
├── flake-modules.nix              root
├── nixosConfigurations.nix        flake.nixosConfigurations      public
├── packages/
│   ├── default.nix                flake.packages                 public
│   └── onehost.nix                flake.packages.onehost         private
├── hosts/
│   ├── default.nix                flake.hosts                    private
│   ├── gandalf.nix                flake.hosts.gandalf            public
│   └── gandalf/
│       └── storage.nix            flake.hosts.gandalf.storage    private
└── users/
    ├── default.nix                flake.users                    private
    ├── alice.nix                  flake.users.alice              public
    └── bob.nix                    flake.users.bob                public
```

`hosts/gandalf.nix` is a file module, so it declares its child as `./gandalf/storage.nix`. Had it been `hosts/gandalf/default.nix`, it would declare `./storage.nix`. Either way, every module has exactly one possible file, so no file is evaluated twice.

**`hosts/default.nix`**
```nix
{ mkFlakeModule, ... }: mkFlakeModule { public = [ ./gandalf.nix ]; } { }
```

### Scopes and Visibility

- `self` is the module's content plus all of its children, public and private.
- `super` is the parent's `self` (`null` at the root).
- `flake` is the root's `self`: the root content plus every top-level module, public and private.
- A child is only ever seen through its **public view**: its content plus its public children. `flake.packages` exposes `x86_64-linux`, but not the private `onehost`.
- The flake outputs are the root's public view.

### Module Arguments

Every module receives:

- every flake input, by name (`nixpkgs`, `home-manager`, …);
- `self`, `super` and `flake`;
- `mkFlakeModule`.

The module's `self` replaces the flake's own `self` input; use `flake` to reach the root scope.

---

## NixOS Modules

When a module's content is a NixOS module (or any module for `lib.evalModules`), declare it with `mkFlakeModule.withNixosModule`:

**`hosts/gandalf/storage.nix`**
```nix
{ mkFlakeModule, ... }:
mkFlakeModule.withNixosModule { } {
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
}
```

`withNixosModule` stamps the NixOS module's `key` and `_file` with the path of the module file. The module system uses `key` to deduplicate imports, and `disabledModules` accepts either that path or the module itself. This matters as soon as a module is imported from more than one place, such as a shared `users` module imported by every user:

**`users/default.nix`**
```nix
{ mkFlakeModule, ... }:
mkFlakeModule.withNixosModule
  {
    public = [
      ./alice.nix
      ./bob.nix
    ];
  }
  (
    { lib, ... }:
    {
      options.example.defaultShell = lib.mkOption {
        type = lib.types.str;
        default = "zsh";
      };
    }
  )
```

**`users/alice.nix`** (`bob.nix` is the same, for Bob)
```nix
{ mkFlakeModule, super, ... }:
mkFlakeModule.withNixosModule { } (
  { config, ... }:
  {
    imports = [ super ];
    users.users.alice = {
      isNormalUser = true;
      description = "Alice, who logs in with ${config.example.defaultShell}";
    };
  }
)
```

Both users import `super`, the `users` module. Without the stamped `key`, NixOS would see two declarations of `example.defaultShell` and fail.

A NixOS module can also have children. They are attached as attributes and stay invisible to the module system:

**`hosts/gandalf.nix`**
```nix
{
  mkFlakeModule,
  self,
  flake,
  ...
}:
mkFlakeModule.withNixosModule { private = [ ./gandalf/storage.nix ]; } {
  imports = [
    self.storage
    flake.users.alice
    flake.users.bob
  ];
  networking.hostName = "gandalf";
}
```

Since the stamped module already defines `key`, `_file`, `__functor` and `__functionArgs`, a `withNixosModule` parent cannot have children with those names.

Finally, the public `nixosConfigurations` module assembles the host:

**`nixosConfigurations.nix`**
```nix
{
  mkFlakeModule,
  flake,
  nixpkgs,
  ...
}:
mkFlakeModule { } {
  gandalf = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ flake.hosts.gandalf ];
  };
}
```

---

## Validation

`flake-modules` checks declarations before importing anything and reports errors against the file that made them:

- **Declarations** must be attribute sets with only `public` and `private`, whose entries are paths. Strings are rejected.
- **Names** must be unique within a module: the same path twice, a path in both lists, or `./x` together with `./x.nix` are all duplicates.
- **Locations**: a child must live directly in its parent's children directory.
- **Files**: a child must be a `.nix` file or a directory containing `default.nix`. Directories whose names end in `.nix` are rejected, and so is a module that exists both as `x.nix` and as `x/default.nix`.
- **Content**: a parent's content must be an attribute set or a function, and must not define an attribute with the same name as a child.
- **Module files** must be functions returning a flake module. Forgetting the content (`mkFlakeModule { }` alone) gets a dedicated error.

Modules are evaluated lazily: declaring a child only checks its path, and its file is imported when something reads it.

---

## API

`flake-modules.lib` exposes:

- `evalFlake rootDir inputs`, or `evalFlake { rootDir; inputs; }`: evaluates the module tree rooted at `rootDir/flake-modules.nix` and returns the flake outputs.
- `mkFlake`: an alias for `evalFlake`.

Everything else, `mkFlakeModule` included, reaches modules as [module arguments](#module-arguments).

## Requirements

- Nix 2.14 or newer.
- No flake inputs: `flake-modules` is written in plain Nix with an empty `inputs = { };`.

---

## License

MIT or Apache-2.0
