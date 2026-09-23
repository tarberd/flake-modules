rec {
  # 1. Monadic builders: createFlakeModule, pubMod, mod
  builder = priv: pub: op:
    if builtins.isAttrs op && op ? __type && op.__type == "createFlakeModule" then
      content: {
        __type = "flakeModule";
        privateModules = priv;
        publicModules = pub;
        inherit content;
      }
    else if builtins.isAttrs op && op ? __type && op.__type == "pubMod" then
      name:
        if !builtins.isString name then
          throw "pubMod expects a string module name, received ${builtins.typeOf name}."
        else if builtins.elem name (priv ++ pub) then
          throw "Duplicate submodule declaration '${name}' in module definition."
        else
          builder priv (pub ++ [ name ])
    else if builtins.isAttrs op && op ? __type && op.__type == "mod" then
      name:
        if !builtins.isString name then
          throw "mod expects a string module name, received ${builtins.typeOf name}."
        else if builtins.elem name (priv ++ pub) then
          throw "Duplicate submodule declaration '${name}' in module definition."
        else
          builder (priv ++ [ name ]) pub
    else
      throw "Unexpected combinator in module definition. Expected 'pubMod', 'mod', or 'createFlakeModule'.";

  pubMod = {
    __type = "pubMod";
    __functor = _: name: builder [] [] pubMod name;
  };

  mod = {
    __type = "mod";
    __functor = _: name: builder [] [] mod name;
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
        inherit createFlakeModule pubMod mod declareNixosModule;
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
  evalFlake = rootDir: inputs: rootMonad:
    let
      evalRootSub = name:
        let
          subPath = resolveSubmodule rootDir name;
        in
          evalModule subPath null flakeRef sharedArgs;

      evaluatedPrivateRoot = evalSubmodules evalRootSub rootMonad.privateModules;
      evaluatedPublicRoot = evalSubmodules evalRootSub rootMonad.publicModules;

      allRootModules = evaluatedPrivateRoot // evaluatedPublicRoot;

      sharedArgs = inputs;
      flakeRef = allRootModules;

      publicOutputs = mergeSubmodules rootDir rootMonad.content evaluatedPublicRoot;
    in
      publicOutputs;

  # 7. High-level convenience wrapper
  mkFlake = { inputs, rootDir, root }:
    evalFlake rootDir inputs (
      if builtins.isFunction root then
        root { inherit pubMod mod createFlakeModule; }
      else
        root
    );
}
