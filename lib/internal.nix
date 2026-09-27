rec {
  # A module node identifies a module file and the directory holding its
  # children: { file; childDir; }. For the root flake-modules.nix and for
  # x/default.nix that is the file's own directory; for x.nix it is x/.

  # 1. Submodule path resolution

  # Derive a module name from a child path: ./foo.nix and ./foo both name "foo"
  childName = path:
    let
      base = baseNameOf path;
      stem = builtins.match "(.*)\\.nix" base;
    in
      if stem == null then base else builtins.head stem;

  invalidEntry = declarer: entry:
    throw "Invalid submodule entry in '${declarer}': expected a path such as ./foo.nix or ./foo, received ${builtins.typeOf entry}.";

  # Validate one declared child of parentNode and compute its module node
  resolveChild = parentNode: path:
    let
      declarer = toString parentNode.file;
      pathStr = toString path;
      name = childName path;
      fileCandidate = dirOf path + "/${name}.nix";
      dirCandidate = dirOf path + "/${name}/default.nix";
      ambiguous = "Ambiguous submodule '${name}' declared in '${declarer}': both '${toString fileCandidate}' and '${toString dirCandidate}' exist.";
      hasDefault = builtins.pathExists (path + "/default.nix");
      isDirectory = hasDefault || builtins.readFileType path == "directory";
      hasNixSuffix = builtins.match ".*\\.nix" (baseNameOf path) != null;
    in
      if !builtins.isPath path then
        invalidEntry declarer path
      else if toString (dirOf path) != toString parentNode.childDir then
        throw "Submodule '${pathStr}' declared in '${declarer}' is outside its children directory '${toString parentNode.childDir}'. Children must live directly in that directory."
      else if !builtins.pathExists path then
        throw "Cannot find submodule '${pathStr}' declared in '${declarer}'."
      else if isDirectory then
        # Only file modules drop the .nix suffix from their name; reject a
        # directory named x.nix rather than guess which name it should get
        if hasNixSuffix then
          throw "Submodule directory '${pathStr}' declared in '${declarer}' has a name ending in .nix. Only file modules end in .nix; rename the directory."
        else if !hasDefault then
          throw "Submodule directory '${pathStr}' declared in '${declarer}' has no default.nix."
        else if builtins.pathExists fileCandidate then
          throw ambiguous
        else
          {
            inherit name;
            node = {
              file = path + "/default.nix";
              childDir = path;
            };
          }
      else if !hasNixSuffix then
        throw "Submodule file '${pathStr}' declared in '${declarer}' must end in .nix."
      else if builtins.pathExists dirCandidate then
        throw ambiguous
      else
        {
          inherit name;
          node = {
            file = path;
            childDir = dirOf path + "/${name}";
          };
        };

  # 2. Module declaration and builder

  # Validate a { public ? [ ]; private ? [ ]; } declaration and resolve its children
  validateDecl = node: kind: decl:
    let
      declarer = toString node.file;
      unknown = builtins.filter (key: !builtins.elem key [ "public" "private" ]) (builtins.attrNames decl);
      entriesOf = key:
        let
          value = decl.${key} or [];
        in
          if builtins.isList value then
            value
          else
            throw "'${key}' in module declaration of '${declarer}' must be a list of paths, received ${builtins.typeOf value}.";
      public = entriesOf "public";
      private = entriesOf "private";
      entries = public ++ private;
      nonPaths = builtins.filter (entry: !builtins.isPath entry) entries;
      names = map childName entries;
      duplicates = builtins.filter (name: builtins.length (builtins.filter (other: other == name) names) > 1) names;
      reserved = builtins.filter (name: builtins.elem name kind.reservedNames) names;
    in
      if !builtins.isAttrs decl then
        throw "Module declaration in '${declarer}' must be an attribute set such as { public = [ ./foo.nix ]; }, received ${builtins.typeOf decl}."
      else if unknown != [] then
        throw "Unknown attributes in module declaration of '${declarer}': ${builtins.concatStringsSep ", " unknown}. Only 'public' and 'private' are allowed."
      else if nonPaths != [] then
        invalidEntry declarer (builtins.head nonPaths)
      else if duplicates != [] then
        throw "Duplicate submodule declaration '${builtins.head duplicates}' in '${declarer}'."
      else if reserved != [] then
        throw "Submodule name '${builtins.head reserved}' declared in '${declarer}' is reserved by ${kind.name}, which already defines ${builtins.concatStringsSep ", " kind.reservedNames} on the module. Rename the child."
      else
        {
          publicModules = map (resolveChild node) public;
          privateModules = map (resolveChild node) private;
        };

  # Content kinds: how a builder transforms its content, and which child
  # names the transformed content already uses
  plainContent = {
    name = "mkFlakeModule";
    transform = content: content;
    reservedNames = [];
  };

  nixosContent = file: {
    name = "mkFlakeModule.withNixosModule";
    transform = declareNixosModuleFor file;
    # The functor returned by declareNixosModuleFor carries these attributes
    reservedNames = [ "key" "_file" "__functor" "__functionArgs" ];
  };

  # Build a flake module value. Validation is lazy: declaration errors surface
  # when the children are read, content errors when the content is read.
  mkModule = node: kind: decl: rawContent:
    let
      children = validateDecl node kind decl;
      hasChildren = children.publicModules != [] || children.privateModules != [];
      content = kind.transform rawContent;
    in
      {
        __type = "flakeModule";
        inherit (children) publicModules privateModules;
        content =
          if hasChildren && !(builtins.isAttrs content || builtins.isFunction content) then
            throw "Module '${toString node.file}' declares submodules, so its content must be an attribute set or a function, received ${builtins.typeOf content}."
          else
            content;
      };

  # A builder is a functor taking a declaration and content of a given kind
  mkBuilder = node: kind: {
    __type = "flakeModuleBuilder";
    __functor = _: decl: content: mkModule node kind decl content;
  };

  # The builder injected as `mkFlakeModule` into the module at `node`.
  # Content kinds are mutually exclusive, so only the base builder has `with*`.
  mkFlakeModuleFor = node:
    mkBuilder node plainContent // {
      withNixosModule = mkBuilder node (nixosContent node.file);
    };

  # 3. NixOS module key/file stamping helper
  declareNixosModuleFor = filePath:
    let
      pathStr = toString filePath;
    in
      module:
        let
          modKey = if builtins.isAttrs module && module ? key then toString module.key else pathStr;
          modFile = if builtins.isAttrs module && module ? _file then toString module._file else pathStr;
        in
          if builtins.isFunction module then
            {
              __functor = _functorSelf: moduleArgs:
                let
                  res = module moduleArgs;
                in
                  {
                    key = modKey;
                    _file = modFile;
                  } // res // {
                    key = res.key or modKey;
                    _file = res._file or modFile;
                  };
              __functionArgs = builtins.functionArgs module;
              key = modKey;
              _file = modFile;
            }
          else if builtins.isAttrs module then
            if module ? __functor then
              {
                __functor = _functorSelf: moduleArgs:
                  let
                    res = module moduleArgs;
                  in
                    {
                      key = modKey;
                      _file = modFile;
                    } // res // {
                      key = res.key or modKey;
                      _file = res._file or modFile;
                    };
                __functionArgs = module.__functionArgs or {};
                key = modKey;
                _file = modFile;
              }
            else
              {
                __functor = _functorSelf: _moduleArgs:
                  {
                    key = modKey;
                    _file = modFile;
                  } // module // {
                    key = module.key or modKey;
                    _file = module._file or modFile;
                  };
                __functionArgs = {};
                key = modKey;
                _file = modFile;
              }
          else
            throw "mkFlakeModule.withNixosModule at '${pathStr}' expects a function or attribute set, received ${builtins.typeOf module}.";

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
          # If content is a function (e.g. mkFlakeModule { public = [ ./x.nix ]; } (args: …)),
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

  # 5. Core module evaluator: returns the module's full scope (`self`,
  # including private children) and its public view
  evalNode = node: superRef: flakeRef: inputs:
    let
      file = toString node.file;

      raw = import node.file;

      moduleArgs = inputs // {
        self = selfRef;
        super = superRef;
        flake = flakeRef;
        mkFlakeModule = mkFlakeModuleFor node;
      };

      evaluated =
        if builtins.isFunction raw then
          raw moduleArgs
        else
          throw "Module '${file}' must be a function taking module arguments, received ${builtins.typeOf raw}.";

      tagOf = value: if builtins.isAttrs value then value.__type or null else null;

      module =
        if tagOf evaluated == "flakeModule" then
          evaluated
        else if tagOf evaluated == "flakeModuleBuilder" then
          throw "Module '${file}' is missing its content: it evaluated to the mkFlakeModule builder itself. Pass a declaration and content, e.g. mkFlakeModule { } content."
        else if builtins.isFunction evaluated then
          throw "Module '${file}' is missing its content: it evaluated to a function. Did you forget the content argument of mkFlakeModule?"
        else
          throw "Module '${file}' did not evaluate to a flake module. Declare it with mkFlakeModule.";

      evalChildren = children:
        builtins.listToAttrs (map (child: {
          inherit (child) name;
          value = (evalNode child.node selfRef flakeRef inputs).public;
        }) children);

      publicChildren = evalChildren module.publicModules;
      privateChildren = evalChildren module.privateModules;

      selfRef = mergeSubmodules file module.content (privateChildren // publicChildren);
      publicRef = mergeSubmodules file module.content publicChildren;
    in
      {
        self = selfRef;
        public = publicRef;
      };

  # 6. Root flake evaluator
  evalFlake = arg1:
    let
      run = rootDir: inputs:
        let
          rootFile = rootDir + "/flake-modules.nix";
          rootNode =
            if !builtins.pathExists rootFile then
              if baseNameOf (toString rootDir) == "flake-modules.nix" then
                throw "flake-modules: evalFlake expects a directory path containing 'flake-modules.nix' (e.g. evalFlake ./. inputs), but received file path '${toString rootDir}'."
              else
                throw "flake-modules: Directory '${toString rootDir}' does not contain 'flake-modules.nix'."
            else
              {
                file = rootFile;
                childDir = rootDir;
              };

          # The root has no parent, and `flake` is the root's own full scope
          root = evalNode rootNode null root.self inputs;
        in
          root.public;
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
