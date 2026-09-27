# `lib` is the public API as consumers see it (flake-modules.lib);
# `internal` is the implementation, imported directly for white-box tests.
{
  lib,
  internal,
  pkgs,
  templatePath ? ../template,
  ...
}:
let
  fixtures = ./fixtures;

  # A module node whose children directory holds the resolution fixtures
  resolutionDir = fixtures + "/resolution";
  resolutionNode = {
    file = resolutionDir + "/default.nix";
    childDir = resolutionDir;
  };
  fileMod = resolutionDir + "/file-mod.nix";
  dirMod = resolutionDir + "/dir-mod";

  # The builder injected into a module living at resolutionNode
  mkFlakeModule = internal.mkFlakeModuleFor resolutionNode;

  childNames = children: map (child: child.name) children;
in
{
  # =========================================================================
  # 1. Module Builder (mkFlakeModuleFor)
  # =========================================================================

  test_builder_tags = {
    expr = {
      builder = mkFlakeModule.__type;
      nixosBuilder = mkFlakeModule.withNixosModule.__type;
      module = (mkFlakeModule { } { }).__type;
    };
    expected = {
      builder = "flakeModuleBuilder";
      nixosBuilder = "flakeModuleBuilder";
      module = "flakeModule";
    };
  };

  test_builder_leaf_literal = {
    expr = (mkFlakeModule { } "hello world").content;
    expected = "hello world";
  };

  test_builder_leaf_attrs = {
    expr = (mkFlakeModule { } { say = "hello world"; }).content;
    expected = {
      say = "hello world";
    };
  };

  test_builder_leaf_function = {
    expr = builtins.isFunction (mkFlakeModule { } (args: args)).content;
    expected = true;
  };

  test_builder_decl_defaults = {
    expr =
      let
        m = mkFlakeModule { } { };
      in
      {
        inherit (m) publicModules privateModules;
      };
    expected = {
      publicModules = [ ];
      privateModules = [ ];
    };
  };

  test_builder_children = {
    expr =
      let
        m = mkFlakeModule {
          public = [ fileMod ];
          private = [ dirMod ];
        } { };
      in
      {
        public = childNames m.publicModules;
        private = childNames m.privateModules;
      };
    expected = {
      public = [ "file-mod" ];
      private = [ "dir-mod" ];
    };
  };

  test_builder_parent_attrs = {
    expr = (mkFlakeModule { public = [ fileMod ]; } { a = 1; }).content;
    expected = {
      a = 1;
    };
  };

  test_builder_parent_function = {
    expr = builtins.isFunction (mkFlakeModule { public = [ fileMod ]; } (args: args)).content;
    expected = true;
  };

  test_error_builder_parent_literal = {
    expr = (mkFlakeModule { public = [ fileMod ]; } "hello world").content;
    expectedError = {
      type = "ThrownError";
      msg = "declares submodules, so its content must be an attribute set or a function, received string";
    };
  };

  test_builder_nixos_leaf = {
    expr =
      let
        m = mkFlakeModule.withNixosModule { } ({ ... }: { });
      in
      {
        key = m.content.key;
        file = m.content._file;
        isFunctor = m.content ? __functor;
      };
    expected = {
      key = toString resolutionNode.file;
      file = toString resolutionNode.file;
      isFunctor = true;
    };
  };

  test_builder_nixos_parent = {
    expr =
      let
        m = mkFlakeModule.withNixosModule { public = [ fileMod ]; } { options = { }; };
      in
      {
        key = m.content.key;
        children = childNames m.publicModules;
      };
    expected = {
      key = toString resolutionNode.file;
      children = [ "file-mod" ];
    };
  };

  test_error_builder_nixos_literal = {
    expr = (mkFlakeModule.withNixosModule { } "hello world").content;
    expectedError = {
      type = "ThrownError";
      msg = "withNixosModule at '.*' expects a function or attribute set, received string";
    };
  };

  test_error_builder_nixos_reserved_child_name = {
    # withNixosModule content already defines key and _file; detected before
    # the file system is consulted
    expr =
      (mkFlakeModule.withNixosModule { public = [ (resolutionDir + "/_file.nix") ]; } { }).publicModules;
    expectedError = {
      type = "ThrownError";
      msg = "Submodule name '_file' declared in '.*' is reserved by mkFlakeModule.withNixosModule";
    };
  };

  test_builder_plain_allows_reserved_nixos_names = {
    expr = childNames (mkFlakeModule { public = [ (resolutionDir + "/key.nix") ]; } { }).publicModules;
    expected = [ "key" ];
  };

  test_builder_with_only_on_base = {
    expr = {
      base = mkFlakeModule ? withNixosModule;
      nixos = mkFlakeModule.withNixosModule ? withNixosModule;
    };
    expected = {
      base = true;
      nixos = false;
    };
  };

  test_error_decl_not_attrs = {
    expr = (mkFlakeModule "apps" { }).publicModules;
    expectedError = {
      type = "ThrownError";
      msg = "Module declaration in '.*' must be an attribute set";
    };
  };

  test_error_decl_unknown_key = {
    expr = (mkFlakeModule { pubic = [ fileMod ]; } { }).publicModules;
    expectedError = {
      type = "ThrownError";
      msg = "Unknown attributes in module declaration of '.*': pubic";
    };
  };

  test_error_decl_not_list = {
    expr = (mkFlakeModule { public = fileMod; } { }).publicModules;
    expectedError = {
      type = "ThrownError";
      msg = "'public' in module declaration of '.*' must be a list of paths, received path";
    };
  };

  test_error_decl_string_entry = {
    expr = (mkFlakeModule { public = [ "file-mod" ]; } { }).publicModules;
    expectedError = {
      type = "ThrownError";
      msg = "Invalid submodule entry in '.*': expected a path";
    };
  };

  test_error_duplicate_same_list = {
    expr =
      (mkFlakeModule {
        public = [
          fileMod
          fileMod
        ];
      } { }).publicModules;
    expectedError = {
      type = "ThrownError";
      msg = "Duplicate submodule declaration 'file-mod'";
    };
  };

  test_error_duplicate_across_lists = {
    expr =
      (mkFlakeModule {
        public = [ fileMod ];
        private = [ fileMod ];
      } { }).privateModules;
    expectedError = {
      type = "ThrownError";
      msg = "Duplicate submodule declaration 'file-mod'";
    };
  };

  test_error_duplicate_file_and_dir = {
    # Duplicate names are detected before the file system is consulted
    expr =
      (mkFlakeModule {
        public = [
          fileMod
          (resolutionDir + "/file-mod")
        ];
      } { }).publicModules;
    expectedError = {
      type = "ThrownError";
      msg = "Duplicate submodule declaration 'file-mod'";
    };
  };

  # =========================================================================
  # 2. Submodule Path Resolution (childName, resolveChild)
  # =========================================================================

  test_child_name_file = {
    expr = internal.childName fileMod;
    expected = "file-mod";
  };

  test_child_name_dir = {
    expr = internal.childName dirMod;
    expected = "dir-mod";
  };

  test_resolve_file = {
    # resolution/file-mod/ exists without a default.nix: it is file-mod.nix's
    # children directory, so resolving file-mod.nix is not ambiguous
    expr =
      let
        child = internal.resolveChild resolutionNode fileMod;
      in
      {
        inherit (child) name;
        file = toString child.node.file;
        childDir = toString child.node.childDir;
      };
    expected = {
      name = "file-mod";
      file = toString fileMod;
      childDir = toString (resolutionDir + "/file-mod");
    };
  };

  test_resolve_dir = {
    expr =
      let
        child = internal.resolveChild resolutionNode dirMod;
      in
      {
        inherit (child) name;
        file = toString child.node.file;
        childDir = toString child.node.childDir;
      };
    expected = {
      name = "dir-mod";
      file = toString (dirMod + "/default.nix");
      childDir = toString dirMod;
    };
  };

  test_resolve_child_of_file_module = {
    # Children of x.nix live in the sibling directory x/
    expr =
      let
        fileParent = (internal.resolveChild resolutionNode fileMod).node;
        child = internal.resolveChild fileParent (resolutionDir + "/file-mod/inner.nix");
      in
      {
        inherit (child) name;
        file = toString child.node.file;
      };
    expected = {
      name = "inner";
      file = toString (resolutionDir + "/file-mod/inner.nix");
    };
  };

  test_resolve_invalid_type = {
    expr = internal.resolveChild resolutionNode "file-mod";
    expectedError = {
      type = "ThrownError";
      msg = "Invalid submodule entry in '.*': expected a path";
    };
  };

  test_resolve_grandchild_rejected = {
    expr = internal.resolveChild resolutionNode (dirMod + "/default.nix");
    expectedError = {
      type = "ThrownError";
      msg = "is outside its children directory";
    };
  };

  test_resolve_sibling_of_file_module_rejected = {
    # A sibling of x.nix belongs to x.nix's parent, not to x.nix
    expr =
      let
        fileParent = (internal.resolveChild resolutionNode fileMod).node;
      in
      internal.resolveChild fileParent dirMod;
    expectedError = {
      type = "ThrownError";
      msg = "is outside its children directory";
    };
  };

  test_resolve_missing = {
    expr = internal.resolveChild resolutionNode (resolutionDir + "/nonexistent.nix");
    expectedError = {
      type = "ThrownError";
      msg = "Cannot find submodule '.*/nonexistent.nix'";
    };
  };

  test_resolve_dir_without_default = {
    expr = internal.resolveChild resolutionNode (resolutionDir + "/no-default");
    expectedError = {
      type = "ThrownError";
      msg = "Submodule directory '.*/no-default' declared in '.*' has no default.nix";
    };
  };

  test_resolve_dir_named_nix = {
    expr = internal.resolveChild resolutionNode (resolutionDir + "/dir-named.nix");
    expectedError = {
      type = "ThrownError";
      msg = "Submodule directory '.*/dir-named.nix' declared in '.*' has a name ending in .nix";
    };
  };

  test_resolve_not_nix_file = {
    expr = internal.resolveChild resolutionNode (resolutionDir + "/not-nix.txt");
    expectedError = {
      type = "ThrownError";
      msg = "Submodule file '.*/not-nix.txt' declared in '.*' must end in .nix";
    };
  };

  test_resolve_ambiguous_from_file = {
    expr = internal.resolveChild resolutionNode (resolutionDir + "/ambiguous.nix");
    expectedError = {
      type = "ThrownError";
      msg = "Ambiguous submodule 'ambiguous'";
    };
  };

  test_resolve_ambiguous_from_dir = {
    expr = internal.resolveChild resolutionNode (resolutionDir + "/ambiguous");
    expectedError = {
      type = "ThrownError";
      msg = "Ambiguous submodule 'ambiguous'";
    };
  };

  # =========================================================================
  # 3. Submodule Merging & Collisions (mergeSubmodules)
  # =========================================================================

  test_merge_empty_submodules = {
    expr = internal.mergeSubmodules "/context" { a = 1; } { };
    expected = {
      a = 1;
    };
  };

  test_merge_attrs = {
    expr = internal.mergeSubmodules "/context" { a = 1; } { b = 2; };
    expected = {
      a = 1;
      b = 2;
    };
  };

  test_merge_function_functor = {
    expr =
      let
        fn = args: { res = args.x + 1; };
        merged = internal.mergeSubmodules "/context" fn { sub = 42; };
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
    expr = internal.mergeSubmodules "/context" { foo = 1; } { foo = 2; };
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
        m = internal.declareNixosModuleFor "/test/mod.nix" ({ lib, ... }: { options.a = 1; });
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
        m = internal.declareNixosModuleFor "/test/mod.nix" { options.a = 1; };
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
        m = internal.declareNixosModuleFor "/test/mod.nix" {
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
    expr = internal.declareNixosModuleFor "/test/mod.nix" 123;
    expectedError = {
      type = "ThrownError";
      msg = "withNixosModule at '/test/mod.nix' expects a function or attribute set, received int.";
    };
  };

  test_nixos_eval_deduplication = {
    expr =
      let
        mod = internal.declareNixosModuleFor "/test/dedup.nix" (
          { lib, ... }: {
            options.testDedup = lib.mkOption {
              type = lib.types.str;
              default = "passed";
            };
          }
        );
        eval = pkgs.lib.evalModules {
          modules = [
            mod
            mod
          ];
        };
      in
      eval.config.testDedup;
    expected = "passed";
  };

  test_nixos_disabled_modules_path = {
    expr =
      let
        mod = internal.declareNixosModuleFor "/test/disabled.nix" (
          { lib, ... }: {
            options.testDisabled = lib.mkOption {
              type = lib.types.str;
              default = "enabled";
            };
          }
        );
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
        mod = internal.declareNixosModuleFor "/test/disabled.nix" (
          { lib, ... }: {
            options.testDisabled = lib.mkOption {
              type = lib.types.str;
              default = "enabled";
            };
          }
        );
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
        attrMod =
          (internal.declareNixosModuleFor "/test/attr.nix" {
            options.foo = pkgs.lib.mkOption {
              type = pkgs.lib.types.int;
              default = 42;
            };
          })
          // {
            attachedSub = {
              kind = "isolated";
            };
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
  # 5. Public API & Root Evaluator Contract (evalFlake)
  # =========================================================================

  test_public_api = {
    expr = builtins.attrNames lib;
    expected = [
      "evalFlake"
      "mkFlake"
    ];
  };

  test_eval_flake_missing_entrypoint = {
    expr = lib.evalFlake (fixtures + "/empty-dir") { };
    expectedError = {
      type = "ThrownError";
      msg = "Directory '.*' does not contain 'flake-modules.nix'.";
    };
  };

  test_eval_flake_file_path_error = {
    expr = lib.evalFlake (fixtures + "/sample-flake/flake-modules.nix") { };
    expectedError = {
      type = "ThrownError";
      msg = "evalFlake expects a directory path containing 'flake-modules.nix'.*but received file path";
    };
  };

  test_eval_flake_privacy_and_scopes = {
    expr =
      let
        outputs = lib.evalFlake (fixtures + "/sample-flake") { };
      in
      {
        hasPublicChild = outputs ? publicChild;
        hasPrivateChild = outputs ? privateChild;
        hasRootVal = outputs ? rootVal;
        publicVal = outputs.publicChild.publicVal;
        privateView = outputs.privateView;
      };
    expected = {
      hasPublicChild = true;
      hasPrivateChild = false;
      hasRootVal = true;
      publicVal = "public";
      privateView = {
        privateVal = "private";
        canSeePublic = "public";
        rootIsSuper = "root";
        hasOwnSelf = true;
      };
    };
  };

  test_eval_flake_attrset_invocation = {
    expr =
      let
        outputs = lib.evalFlake {
          rootDir = fixtures + "/sample-flake";
          inputs = { };
        };
      in
      outputs.publicChild.publicVal;
    expected = "public";
  };

  test_eval_flake_file_layout = {
    # alice/bob.nix declares its child as ./bob/charlie.nix
    expr =
      let
        outputs = lib.evalFlake (fixtures + "/layouts/file-layout") { };
      in
      {
        hasPrivateCharlie = outputs.alice.bob ? charlie;
        charlie = outputs.alice.bob.charlieView;
      };
    expected = {
      hasPrivateCharlie = false;
      charlie = {
        name = "charlie";
        selfName = "charlie";
        superName = "bob";
        aliceName = "alice";
        rootMarker = "root";
      };
    };
  };

  test_eval_flake_dir_layout = {
    # alice/bob/default.nix declares its child as ./charlie.nix
    expr =
      let
        outputs = lib.evalFlake (fixtures + "/layouts/dir-layout") { };
      in
      {
        hasPrivateCharlie = outputs.alice.bob ? charlie;
        charlie = outputs.alice.bob.charlieView;
      };
    expected = {
      hasPrivateCharlie = false;
      charlie = {
        name = "charlie";
        selfName = "charlie";
        superName = "bob";
        aliceName = "alice";
        rootMarker = "root";
      };
    };
  };

  test_eval_flake_nixos_keys = {
    expr =
      let
        outputs = lib.evalFlake (fixtures + "/nixos") { };
      in
      {
        leafKey = outputs.leaf.key;
        parentKey = outputs.parent.key;
        parentFile = outputs.parent._file;
      };
    expected = {
      leafKey = toString (fixtures + "/nixos/leaf.nix");
      parentKey = toString (fixtures + "/nixos/parent/default.nix");
      parentFile = toString (fixtures + "/nixos/parent/default.nix");
    };
  };

  test_eval_flake_nixos_modules_evaluate = {
    # The parent's attached child must stay invisible to evalModules
    expr =
      let
        outputs = lib.evalFlake (fixtures + "/nixos") { };
        eval = pkgs.lib.evalModules {
          modules = [
            outputs.leaf
            outputs.parent
          ];
        };
      in
      {
        inherit (eval.config) leafOption parentOption;
        child = outputs.parent.child;
      };
    expected = {
      leafOption = "leaf";
      parentOption = "parent";
      child = "child";
    };
  };

  test_eval_flake_module_args = {
    # Flakes always pass their own `self` input; the module's `self` replaces it
    expr = lib.evalFlake (fixtures + "/module-args") {
      self = "consumer flake self";
      someInput = "input";
    };
    expected = {
      argNames = [
        "flake"
        "mkFlakeModule"
        "self"
        "someInput"
        "super"
      ];
      selfIsModuleScope = true;
    };
  };

  test_eval_flake_error_not_function = {
    expr = lib.evalFlake (fixtures + "/errors/not-function") { };
    expectedError = {
      type = "ThrownError";
      msg = "must be a function taking module arguments, received set";
    };
  };

  test_eval_flake_error_not_flake_module = {
    expr = lib.evalFlake (fixtures + "/errors/not-flake-module") { };
    expectedError = {
      type = "ThrownError";
      msg = "did not evaluate to a flake module";
    };
  };

  test_eval_flake_error_builder_returned = {
    expr = lib.evalFlake (fixtures + "/errors/builder-returned") { };
    expectedError = {
      type = "ThrownError";
      msg = "is missing its content: it evaluated to the mkFlakeModule builder";
    };
  };

  test_eval_flake_error_missing_content = {
    expr = lib.evalFlake (fixtures + "/errors/missing-content") { };
    expectedError = {
      type = "ThrownError";
      msg = "is missing its content: it evaluated to a function";
    };
  };

  # =========================================================================
  # 6. Starter Template Contract
  # =========================================================================

  test_template_evaluates = {
    expr =
      let
        outputs = lib.evalFlake templatePath { };
      in
      outputs ? packages;
    expected = true;
  };
}
