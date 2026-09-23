rec {
  # 1. Monadic builders: createFlakeModule, pub, mod
  builder = priv: pubList: op:
    if builtins.isAttrs op && op ? __type && op.__type == "createFlakeModule" then
      content: {
        __type = "flakeModule";
        privateModules = priv;
        publicModules = pubList;
        inherit content;
      }
    else if builtins.isAttrs op && op ? __type && op.__type == "mod" then
      name:
        if !builtins.isString name then
          throw "mod expects a string module name, received ${builtins.typeOf name}."
        else if builtins.elem name (priv ++ pubList) then
          throw "Duplicate submodule declaration '${name}' in module definition."
        else
          builder (priv ++ [ name ]) pubList
    else if builtins.isAttrs op && op ? __type && op.__type == "pub" then
      subOp:
        if !builtins.isAttrs subOp || !subOp ? __type || subOp.__type != "mod" then
          throw "Expected 'mod' after 'pub' (e.g. pub mod \"name\"), received ${builtins.typeOf subOp}."
        else
          name:
            if !builtins.isString name then
              throw "pub mod expects a string module name, received ${builtins.typeOf name}."
            else if builtins.elem name (priv ++ pubList) then
              throw "Duplicate submodule declaration '${name}' in module definition."
            else
              builder priv (pubList ++ [ name ])
    else
      throw "Unexpected combinator in module definition. Expected 'mod', 'pub mod', or 'createFlakeModule'.";

  pub = {
    __type = "pub";
    __functor = _: subOp:
      if !builtins.isAttrs subOp || !subOp ? __type || subOp.__type != "mod" then
        throw "Expected 'mod' after 'pub' (e.g. pub mod \"name\"), received ${builtins.typeOf subOp}."
      else
        name:
          if !builtins.isString name then
            throw "pub mod expects a string module name, received ${builtins.typeOf name}."
          else
            builder [] [ name ];
  };

  mod = {
    __type = "mod";
    __functor = _: name:
      if !builtins.isString name then
        throw "mod expects a string module name, received ${builtins.typeOf name}."
      else
        builder [ name ] [];
  };

  createFlakeModule = {
    __type = "createFlakeModule";
    __functor = _: builder [] [] createFlakeModule;
  };

  # 2. Submodule path resolution
  resolveSubmodule = parentDir: name:
    if !builtins.isString name then
      throw "Invalid submodule name in '${toString parentDir}'. Expected a string name, got ${builtins.typeOf name}."
    else
      let
        fileCandidate = parentDir + "/${name}.nix";
        dirCandidate = parentDir + "/${name}/default.nix";
        fileExists = builtins.pathExists fileCandidate;
        dirExists = builtins.pathExists dirCandidate;
      in
        if fileExists && dirExists then
          throw "Ambiguous submodule '${name}' in '${toString parentDir}': both '${toString fileCandidate}' and '${toString dirCandidate}' exist."
        else if fileExists then
          fileCandidate
        else if dirExists then
          dirCandidate
        else
          throw "Cannot find submodule '${name}' in '${toString parentDir}'. Looked for '${toString fileCandidate}' and '${toString dirCandidate}'.";

  # 3. NixOS module key/file stamping helper
  declareNixosModuleFor = filePath:
    let
      fileKey = builtins.hashString "sha256" (toString filePath);
    in
      module:
        if builtins.isFunction module then
          {
            __functor = _functorSelf: moduleArgs: (module moduleArgs) // {
              key = fileKey;
              _file = toString filePath;
            };
            __functionArgs = builtins.functionArgs module;
          }
        else if builtins.isAttrs module then
          module // {
            key = fileKey;
            _file = toString filePath;
          }
        else
          throw "declareNixosModule at '${toString filePath}' expects a function or attribute set, received ${builtins.typeOf module}.";

  # 4. Helper to merge submodules onto content
  mergeSubmodules = contextPath: base: subs:
    if subs == {} then
      base
    else
      let
        collisions =
          if builtins.isAttrs base then
            builtins.filter (name: builtins.hasAttr name base) (builtins.attrNames subs)
          else
            [];
      in
        if collisions != [] then
          throw "Submodule name collision in '${toString contextPath}': attributes '${toString collisions}' are defined in both module content and submodules."
        else if builtins.isFunction base then
          # If content is a function (e.g. createFlakeModule ({}: {})),
          # convert it to a functor so submodules can be attached as attributes
          # while the function remains callable
          {
            __functor = _: args: base args;
            __functionArgs = builtins.functionArgs base;
          } // subs
        else if builtins.isAttrs base then
          base // subs
        else
          throw "Cannot attach submodules to non-attribute set content at '${toString contextPath}'.";

  # Helper to evaluate a list of submodule names into an attribute set
  evalSubmodules = evalFn: list:
    builtins.listToAttrs (map (name: {
      inherit name;
      value = evalFn name;
    }) list);

  # 5. Core module evaluator
  evalModule = modulePath: superRef: flakeRef: sharedArgs:
    let
      parentDir = builtins.dirOf modulePath;
      declareNixosModule = declareNixosModuleFor modulePath;

      raw = import modulePath;

      moduleArgs = sharedArgs // {
        self = selfRef;
        super = superRef;
        flake = flakeRef;
        inherit createFlakeModule pub mod declareNixosModule;
      };

      evaluated =
        if builtins.isFunction raw then
          raw moduleArgs
        else
          raw;

      monad =
        if builtins.isAttrs evaluated && evaluated ? __type && evaluated.__type == "flakeModule" then
          evaluated
        else
          throw "Module at ${toString modulePath} did not evaluate to a FlakeModule. Every module in this flake must be declared using 'createFlakeModule'.";

      evalSub = name:
        let
          subPath = resolveSubmodule parentDir name;
        in
          evalModule subPath selfRef flakeRef sharedArgs;

      evaluatedPrivate = evalSubmodules evalSub monad.privateModules;
      evaluatedPublic = evalSubmodules evalSub monad.publicModules;

      allSubmodules = evaluatedPrivate // evaluatedPublic;

      selfRef = mergeSubmodules modulePath monad.content allSubmodules;
      publicRef = mergeSubmodules modulePath monad.content evaluatedPublic;
    in
      publicRef;

  # 6. Root flake evaluator
  evalFlake = arg1:
    let
      run = rootDir: inputs:
        let
          rootFile = rootDir + "/flake-modules.nix";
          resolvedRootFile =
            if !builtins.pathExists rootFile then
              if baseNameOf (toString rootDir) == "flake-modules.nix" then
                throw "flake-modules: evalFlake expects a directory path containing 'flake-modules.nix' (e.g. evalFlake ./. inputs), but received file path '${toString rootDir}'."
              else
                throw "flake-modules: Directory '${toString rootDir}' does not contain 'flake-modules.nix'."
            else
              rootFile;

          declareNixosModule = declareNixosModuleFor resolvedRootFile;

          raw = import resolvedRootFile;

          moduleArgs = sharedArgs // {
            self = selfRef;
            super = null;
            flake = flakeRef;
            inherit createFlakeModule pub mod declareNixosModule;
          };

          evaluated =
            if builtins.isFunction raw then
              raw moduleArgs
            else
              raw;

          monad =
            if builtins.isAttrs evaluated && evaluated ? __type && evaluated.__type == "flakeModule" then
              evaluated
            else
              throw "Root module at '${toString resolvedRootFile}' did not evaluate to a FlakeModule. It must be declared using 'createFlakeModule'.";

          evalSub = name:
            let
              subPath = resolveSubmodule rootDir name;
            in
              evalModule subPath selfRef flakeRef sharedArgs;

          evaluatedPrivate = evalSubmodules evalSub monad.privateModules;
          evaluatedPublic = evalSubmodules evalSub monad.publicModules;

          allSubmodules = evaluatedPrivate // evaluatedPublic;

          sharedArgs = inputs;
          selfRef = mergeSubmodules resolvedRootFile monad.content allSubmodules;
          flakeRef = selfRef;

          publicOutputs = mergeSubmodules resolvedRootFile monad.content evaluatedPublic;
        in
          publicOutputs;
    in
      if builtins.isAttrs arg1 && arg1 ? inputs then
        let
          rootDir =
            if arg1 ? rootDir then
              arg1.rootDir
            else
              throw "flake-modules.evalFlake: Attribute set invocation expects 'rootDir'.";
        in
          run rootDir arg1.inputs
      else
        # Curried invocation: evalFlake rootDir inputs
        inputs: run arg1 inputs;

  # 7. High-level convenience alias
  mkFlake = evalFlake;
}
