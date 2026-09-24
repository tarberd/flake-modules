{
  lib,
  pkgs,
  templatePath ? ../template,
  ...
}:
let
  fixtures = ./fixtures;
in
{
  # =========================================================================
  # 1. Combinators & Monadic Syntax (pub, mod, createFlakeModule)
  # =========================================================================

  test_mod_single = {
    expr = (lib.mod "foo" lib.createFlakeModule {}).privateModules;
    expected = [ "foo" ];
  };

  test_pub_mod_single = {
    expr = (lib.pub lib.mod "foo" lib.createFlakeModule {}).publicModules;
    expected = [ "foo" ];
  };

  test_chaining_order_and_privacy = {
    expr =
      let
        m = lib.mod "priv1" lib.pub lib.mod "pub1" lib.mod "priv2" lib.pub lib.mod "pub2" lib.createFlakeModule {};
      in
      {
        priv = m.privateModules;
        pub = m.publicModules;
      };
    expected = {
      priv = [ "priv1" "priv2" ];
      pub = [ "pub1" "pub2" ];
    };
  };

  test_create_flake_module_empty = {
    expr =
      let
        m = lib.createFlakeModule {};
      in
      {
        inherit (m) privateModules publicModules content;
      };
    expected = {
      privateModules = [];
      publicModules = [];
      content = {};
    };
  };

  test_create_flake_module_function_content = {
    expr = builtins.isFunction (lib.createFlakeModule (args: { inherit args; })).content;
    expected = true;
  };

  test_error_non_string_mod = {
    expr = lib.mod 123;
    expectedError = {
      type = "ThrownError";
      msg = "mod expects a string module name, received int.";
    };
  };

  test_error_non_string_pub_mod = {
    expr = lib.pub lib.mod [ "foo" ];
    expectedError = {
      type = "ThrownError";
      msg = "pub mod expects a string module name, received list.";
    };
  };

  test_error_missing_mod_after_pub = {
    expr = lib.pub "foo";
    expectedError = {
      type = "ThrownError";
      msg = "Expected 'mod' after 'pub'";
    };
  };

  test_error_duplicate_mod = {
    expr = lib.mod "a" lib.mod "a" lib.createFlakeModule {};
    expectedError = {
      type = "ThrownError";
      msg = "Duplicate submodule declaration 'a' in module definition.";
    };
  };

  test_error_duplicate_pub_mod = {
    expr = lib.pub lib.mod "a" lib.pub lib.mod "a" lib.createFlakeModule {};
    expectedError = {
      type = "ThrownError";
      msg = "Duplicate submodule declaration 'a' in module definition.";
    };
  };

  test_error_duplicate_mixed = {
    expr = lib.pub lib.mod "a" lib.mod "a" lib.createFlakeModule {};
    expectedError = {
      type = "ThrownError";
      msg = "Duplicate submodule declaration 'a' in module definition.";
    };
  };

  test_error_unexpected_combinator = {
    expr = (lib.mod "a") 42;
    expectedError = {
      type = "ThrownError";
      msg = "Unexpected combinator in module definition. Expected 'mod', 'pub mod', or 'createFlakeModule'.";
    };
  };

  # =========================================================================
  # 2. Submodule Path Resolution (resolveSubmodule)
  # =========================================================================

  test_resolve_file = {
    expr = toString (lib.resolveSubmodule (fixtures + "/resolution") "file-mod");
    expected = toString (fixtures + "/resolution/file-mod.nix");
  };

  test_resolve_dir = {
    expr = toString (lib.resolveSubmodule (fixtures + "/resolution") "dir-mod");
    expected = toString (fixtures + "/resolution/dir-mod/default.nix");
  };

  test_resolve_missing = {
    expr = lib.resolveSubmodule (fixtures + "/resolution") "nonexistent";
    expectedError = {
      type = "ThrownError";
      msg = "Cannot find submodule 'nonexistent'";
    };
  };

  test_resolve_ambiguous = {
    expr = lib.resolveSubmodule (fixtures + "/resolution") "ambiguous";
    expectedError = {
      type = "ThrownError";
      msg = "Ambiguous submodule 'ambiguous'";
    };
  };

  test_resolve_invalid_name_type = {
    expr = lib.resolveSubmodule (fixtures + "/resolution") 123;
    expectedError = {
      type = "ThrownError";
      msg = "Invalid submodule name";
    };
  };

  # =========================================================================
  # 3. Submodule Merging & Collisions (mergeSubmodules)
  # =========================================================================

  test_merge_empty_submodules = {
    expr = lib.mergeSubmodules "/context" { a = 1; } {};
    expected = { a = 1; };
  };

  test_merge_attrs = {
    expr = lib.mergeSubmodules "/context" { a = 1; } { b = 2; };
    expected = { a = 1; b = 2; };
  };

  test_merge_function_functor = {
    expr =
      let
        fn = args: { res = args.x + 1; };
        merged = lib.mergeSubmodules "/context" fn { sub = 42; };
      in
      {
        computed = (merged { x = 10; }).res;
        subAccess = merged.sub;
      };
    expected = {
      computed = 11;
      subAccess = 42;
    };
  };

  test_error_submodule_content_collision = {
    expr = lib.mergeSubmodules "/context" { foo = 1; } { foo = 2; };
    expectedError = {
      type = "ThrownError";
      msg = "Submodule name collision in '/context': attributes 'foo' are defined in both module content and submodules.";
    };
  };

  # =========================================================================
  # 4. NixOS Module Stamping & Protocol (declareNixosModuleFor)
  # =========================================================================

  test_declare_nixos_module_fn_keys = {
    expr =
      let
        m = lib.declareNixosModuleFor "/test/mod.nix" ({ lib, ... }: { options.a = 1; });
      in
      {
        key = m.key;
        file = m._file;
        isFunctor = m ? __functor;
      };
    expected = {
      key = "/test/mod.nix";
      file = "/test/mod.nix";
      isFunctor = true;
    };
  };

  test_declare_nixos_module_attrs_functor = {
    expr =
      let
        m = lib.declareNixosModuleFor "/test/mod.nix" { options.a = 1; };
      in
      {
        key = m.key;
        file = m._file;
        isFunctor = m ? __functor;
      };
    expected = {
      key = "/test/mod.nix";
      file = "/test/mod.nix";
      isFunctor = true;
    };
  };

  test_declare_nixos_module_custom_overrides = {
    expr =
      let
        m = lib.declareNixosModuleFor "/test/mod.nix" {
          key = "/custom-key.nix";
          _file = "/custom-file.nix";
        };
      in
      {
        key = m.key;
        file = m._file;
      };
    expected = {
      key = "/custom-key.nix";
      file = "/custom-file.nix";
    };
  };

  test_declare_nixos_module_invalid_type = {
    expr = lib.declareNixosModuleFor "/test/mod.nix" 123;
    expectedError = {
      type = "ThrownError";
      msg = "declareNixosModule at '/test/mod.nix' expects a function or attribute set, received int.";
    };
  };

  test_nixos_eval_deduplication = {
    expr =
      let
        mod = lib.declareNixosModuleFor "/test/dedup.nix" ({ lib, ... }: {
          options.testDedup = lib.mkOption { type = lib.types.str; default = "passed"; };
        });
        eval = pkgs.lib.evalModules {
          modules = [ mod mod ];
        };
      in
      eval.config.testDedup;
    expected = "passed";
  };

  test_nixos_disabled_modules_path = {
    expr =
      let
        mod = lib.declareNixosModuleFor "/test/disabled.nix" ({ lib, ... }: {
          options.testDisabled = lib.mkOption { type = lib.types.str; default = "enabled"; };
        });
        eval = pkgs.lib.evalModules {
          modules = [
            mod
            { disabledModules = [ "/test/disabled.nix" ]; }
          ];
        };
      in
      eval.options ? testDisabled;
    expected = false;
  };

  test_nixos_disabled_modules_ref = {
    expr =
      let
        mod = lib.declareNixosModuleFor "/test/disabled.nix" ({ lib, ... }: {
          options.testDisabled = lib.mkOption { type = lib.types.str; default = "enabled"; };
        });
        eval = pkgs.lib.evalModules {
          modules = [
            mod
            { disabledModules = [ mod ]; }
          ];
        };
      in
      eval.options ? testDisabled;
    expected = false;
  };

  test_nixos_submodule_isolation = {
    expr =
      let
        attrMod = (lib.declareNixosModuleFor "/test/attr.nix" {
          options.foo = pkgs.lib.mkOption { type = pkgs.lib.types.int; default = 42; };
        }) // {
          attachedSub = { kind = "isolated"; };
        };
        eval = pkgs.lib.evalModules {
          modules = [ attrMod ];
        };
      in
      {
        configFoo = eval.config.foo;
        subAccess = attrMod.attachedSub.kind;
      };
    expected = {
      configFoo = 42;
      subAccess = "isolated";
    };
  };

  # =========================================================================
  # 5. Root Evaluator Contract (evalFlake)
  # =========================================================================

  test_eval_flake_missing_entrypoint = {
    expr = lib.evalFlake (fixtures + "/empty-dir") {};
    expectedError = {
      type = "ThrownError";
      msg = "Directory '.*' does not contain 'flake-modules.nix'.";
    };
  };

  test_eval_flake_file_path_error = {
    expr = lib.evalFlake (fixtures + "/sample-flake/flake-modules.nix") {};
    expectedError = {
      type = "ThrownError";
      msg = "evalFlake expects a directory path containing 'flake-modules.nix'.*but received file path";
    };
  };

  test_eval_flake_privacy_and_scopes = {
    expr =
      let
        outputs = lib.evalFlake (fixtures + "/sample-flake") {};
      in
      {
        hasPublicChild = outputs ? publicChild;
        hasPrivateChild = outputs ? privateChild;
        hasRootVal = outputs ? rootVal;
        publicVal = outputs.publicChild.publicVal;
      };
    expected = {
      hasPublicChild = true;
      hasPrivateChild = false;
      hasRootVal = true;
      publicVal = "public";
    };
  };

  test_eval_flake_attrset_invocation = {
    expr =
      let
        outputs = lib.evalFlake {
          rootDir = fixtures + "/sample-flake";
          inputs = {};
        };
      in
      outputs.publicChild.publicVal;
    expected = "public";
  };

  # =========================================================================
  # 6. Starter Template Contract
  # =========================================================================

  test_template_evaluates = {
    expr =
      let
        outputs = lib.evalFlake templatePath {};
      in
      outputs ? packages;
    expected = true;
  };
}
