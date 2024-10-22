let
  packages = builtins.fromJSON (builtins.readFile ../packages.json);
in
  (final: prev: 
    builtins.listToAttrs (map (pkg: {
      name = pkg.name;
      value = builtins.fetchClosure {
        fromStore = pkg.fromStore;
        fromPath = pkg.fromPath;
      };
    }) packages)
  )