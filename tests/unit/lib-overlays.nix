# SPDX-License-Identifier: MIT
{
  lib,
  inputs ? { },
}:
let
  # The passed lib is the composed library from the unit test flake,
  # with the framework namespaces: `caisson-core` (machinery,
  # registry, manifest) and `caisson` (the integrations).
  mkFlakePartsModule = lib.caisson.flake-parts.mkModule;
  mkLibOverlay = lib.caisson-core.mkLibOverlay;
  mkModule = lib.caisson-core.mkModule;

  # caisson's flake-parts integration overlay, recovered from this
  # composition's manifest, so test compositions can register it
  # the way a consumer registering the exported overlay would.
  flakePartsOverlay = lib.caisson-core.libManifest.libOverlays.flake-parts;
  structuralOverlay = lib.caisson-core.libManifest.libOverlays.structural;

  # Test-facing mkLib: registers the flake-parts and structural
  # integrations into every test composition (so composed test
  # libraries have caisson.flake-parts.mkTopConfiguration and
  # caisson.structural.mkTopConfiguration), and otherwise defers to
  # caisson-core.mkLib.
  # Malformed arguments pass through untouched so the machinery's
  # shape errors stay observable.
  testMkLib =
    args:
    let
      raw = args.libOverlays or (_lib: { });
    in
    if !(builtins.isAttrs args) || !(builtins.isFunction raw) then
      lib.caisson-core.mkLib args
    else
      lib.caisson-core.mkLib (
        args
        // {
          libOverlays =
            coreLib:
            {
              flake-parts = flakePartsOverlay;
              structural = structuralOverlay;
            }
            // raw coreLib;
        }
      );

  # The names the test bodies use: the caisson namespace, with the
  # machinery reachable at its top level as well as under
  # `caisson-core`.
  caisson = lib.caisson // {
    inherit (lib.caisson-core) mkLibOverlay mkModule importApply;
    mkLib = testMkLib;
  };

  mockDependencies = {
    # The real nixpkgs.lib mirror, a source tree with lib/, which the
    # nixpkgs-lib entry reads by input name. Its `lib` is what test
    # bodies read.
    nixpkgs-lib = inputs.nixpkgs-lib;
  }
  // (
    if inputs ? parent-flake-parts then
      { flake-parts = inputs.parent-flake-parts; }
    else if inputs ? flake-parts then
      { flake-parts = inputs.flake-parts; }
    else
      { }
  );

  mkTestLib =
    {
      libOverlays ? { },
      ...
    }@args:
    caisson.mkLib ({ dependencies = mockDependencies; } // args);

  # The errors Nix raises when a call does not match the pattern of an
  # entry point, as `expectedError` values: the entry point is named
  # in the message, so `fn` is the binding the pattern is written
  # under. `[^']*` steps over the colour codes the evaluator puts
  # inside the quotes; `name` may be an alternation, for a call that
  # leaves more than one required argument out.
  argumentError = fn: kind: name: {
    type = "TypeError";
    msg = "function '[^']*${fn}[^']*' called ${kind} argument '[^']*${name}[^']*'";
  };
  missingArgument = fn: argumentError fn "without required";
  unexpectedArgument = fn: argumentError fn "with unexpected";

  # Package configs for a composition whose package sets are stand-in
  # values: `pkgSets` on mkLib, declaring a config per name whose set
  # for x86_64-linux is the value given.
  stubPkgSets =
    sets: _lib:
    builtins.mapAttrs (
      _: pkgs:
      { name, parent }:
      {
        _type = "caisson-manifest";
        type = "nixpkgs";
        inherit name parent;
        children.nixpkgs.x86_64-linux = {
          _type = "caisson-manifest";
          type = "nixpkgs";
          name = "x86_64-linux";
          value = pkgs;
        };
      }
    ) sets;

  # The value of an option of the type `type` that a single module defines
  # as `value`.
  moduleOption =
    type: value:
    (lib.evalModules {
      modules = [
        {
          options.value = lib.mkOption { inherit type; };
          config.value = value;
        }
      ];
    }).config.value;

  # The integrations the parent registers, each with its entry
  # points.
  integrationNames = [
    "nixos"
    "nixos-minimal"
    "nixos-test"
    "darwin"
    "hjem"
    "home-manager"
    "home-manager-minimal"
    "flake-parts"
    "structural"
    "caisson-colmena"
    "caisson-disko"
    "disko"
    "caisson-facter"
    "facter"
    "caisson-microvm"
    "microvm"
    "caisson-nixops4-composite"
    "caisson-nixops4-resource"
    "terranix"
    "system-manager"
    "treefmt"
    "nvf"
    "nixvim"
    "topology"
    "kubenix"
    "nixidy"
  ];

in
{
  importApply = {
    "test: applies static args to a function" = {
      expr =
        let
          fn = args: { result = args.x + args.y; };
          applied = caisson.importApply fn {
            x = 1;
            y = 2;
          };
        in
        applied.result;
      expected = 3;
    };

    "test: preserves wrapper metadata while applying args" = {
      expr =
        let
          wrappedModule = {
            _file = "wrapper";
            imports = [
              (args: { result = args.x; })
            ];
          };
          applied = caisson.importApply wrappedModule { x = 7; };
        in
        {
          file = applied._file;
          result = (builtins.head applied.imports).result;
        };
      expected = {
        file = "wrapper";
        result = 7;
      };
    };

    "test: handles nested wrappers while applying args" = {
      expr =
        let
          wrappedModule = {
            _file = "outer";
            imports = [
              {
                _file = "inner";
                imports = [
                  (args: { result = args.x + 1; })
                ];
              }
            ];
          };
          applied = caisson.importApply wrappedModule { x = 4; };
        in
        {
          outerFile = applied._file;
          innerFile = (builtins.head applied.imports)._file;
          result = (builtins.head (builtins.head applied.imports).imports).result;
        };
      expected = {
        outerFile = "outer";
        innerFile = "inner";
        result = 5;
      };
    };

    "test: wraps path imports with _file and imports" = {
      expr =
        let
          modulePath = builtins.toFile "import-apply-path-module.nix" ''
            args: { result = args.x * 2; }
          '';
          applied = caisson.importApply modulePath { x = 4; };
        in
        {
          file = builtins.toString applied._file;
          result = (builtins.head applied.imports).result;
        };
      expected =
        let
          modulePath = builtins.toFile "import-apply-path-module.nix" ''
            args: { result = args.x * 2; }
          '';
        in
        {
          file = builtins.toString modulePath;
          result = 8;
        };
    };

    "test: handles path imports that already contain wrappers" = {
      expr =
        let
          modulePath = builtins.toFile "import-apply-wrapped-path-module.nix" ''
            {
              _file = "inner-module";
              imports = [ (args: { result = args.msg; }) ];
            }
          '';
          applied = caisson.importApply modulePath { msg = "ok"; };
        in
        {
          outerFile = builtins.toString applied._file;
          innerFile = (builtins.head applied.imports)._file;
          result = (builtins.head (builtins.head applied.imports).imports).result;
        };
      expected =
        let
          modulePath = builtins.toFile "import-apply-wrapped-path-module.nix" ''
            {
              _file = "inner-module";
              imports = [ (args: { result = args.msg; }) ];
            }
          '';
        in
        {
          outerFile = builtins.toString modulePath;
          innerFile = "inner-module";
          result = "ok";
        };
    };

    "test: works when function ignores provided args" = {
      expr =
        let
          fn = _args: { fixed = true; };
          applied = caisson.importApply fn { ignored = 1; };
        in
        applied.fixed;
      expected = true;
    };

  };

  mkModule = {
    "test: applies the flat closure attrset" = {
      expr =
        let
          module =
            {
              closure-lib,
              mkModule,
              ...
            }:
            { config, ... }:
            {
              hasDependencies = builtins.isAttrs closure-lib.caisson.dependencies;
              hasLib = builtins.isAttrs closure-lib;
              hasMkMod = builtins.isFunction mkModule;
            };
          result = mkFlakePartsModule module;
          evaluated = result { config = { }; };
        in
        evaluated.hasDependencies && evaluated.hasLib && evaluated.hasMkMod;
      expected = true;
    };

    "test: closure args can be ignored with an open pattern" = {
      expr =
        let
          module =
            { ... }:
            { config, ... }:
            {
              ok = true;
            };
          evaluated = (mkFlakePartsModule module) { config = { }; };
        in
        evaluated.ok;
      expected = true;
    };

    "test: throws on a plain attrset module" = {
      expr = builtins.tryEval (mkFlakePartsModule {
        options = { };
      });
      expected = {
        success = false;
        value = false;
      };
    };

    "test: path modules get _file and a path-based dedup key" = {
      expr =
        let
          modulePath = builtins.toFile "mk-module-path-module.nix" ''
            { ... }: { config, ... }: { ok = true; }
          '';
          result = mkFlakePartsModule modulePath;
        in
        {
          file = builtins.toString result._file;
          key = result.key;
          ok = ((builtins.head result.imports) { config = { }; }).ok;
        };
      expected =
        let
          modulePath = builtins.toFile "mk-module-path-module.nix" ''
            { ... }: { config, ... }: { ok = true; }
          '';
        in
        {
          file = builtins.toString modulePath;
          key = builtins.toString modulePath;
          ok = true;
        };
    };

    "test: the same path wrapped twice yields the same key" = {
      expr =
        let
          modulePath = builtins.toFile "mk-module-dedup-module.nix" ''
            { ... }: { config, ... }: { ok = true; }
          '';
          a = mkFlakePartsModule modulePath;
          b = mkFlakePartsModule modulePath;
        in
        a.key == b.key;
      expected = true;
    };

    "test: handles wrapped module with _file and imports" = {
      expr =
        let
          innerModule =
            { mkModule, ... }:
            { config, ... }:
            {
              hasMkMod = builtins.isFunction mkModule;
            };
          wrapped = {
            _file = "test-wrapper";
            imports = [ innerModule ];
          };
          result = mkFlakePartsModule wrapped;
        in
        builtins.isAttrs result && builtins.hasAttr "_file" result && builtins.hasAttr "imports" result;
      expected = true;
    };
  };

  mkModuleFactory = {
    "test: mkModule returns class-specific normalizer" = {
      expr = builtins.isFunction (caisson.mkModule "test-class");
      expected = true;
    };

    "test: class-specific mkModule closes nested mkModule over same class" = {
      expr =
        let
          mkTestClassModule = caisson.mkModule "test-class";
          module =
            { mkModule, ... }:
            { config, ... }:
            let
              nested = mkModule (
                nestedClosure:
                { config, ... }:
                let
                  nestedResult =
                    (nestedClosure.mkModule (
                      { ... }:
                      { config, ... }:
                      {
                        nestedOk = true;
                      }
                    ))
                      { config = { }; };
                in
                {
                  nestedMkModProducesModule = nestedResult.nestedOk or false;
                }
              );
              nestedResult = nested { config = { }; };
            in
            {
              nestedMkModProducesModule = nestedResult.nestedMkModProducesModule or false;
            };
          result = (mkTestClassModule module) { config = { }; };
        in
        result.nestedMkModProducesModule;
      expected = true;
    };

    "test: class-specific mkModule closures are independent across classes" = {
      expr =
        let
          mkClassA = caisson.mkModule "class-a";
          mkClassB = caisson.mkModule "class-b";

          classModule =
            classLabel:
            { mkModule, ... }:
            { config, ... }:
            let
              nested = mkModule (
                { ... }:
                { config, ... }:
                {
                  nestedLabel = classLabel;
                }
              );
              nestedResult = nested { config = { }; };
            in
            {
              label = classLabel;
              inherit (nestedResult) nestedLabel;
            };

          resultA = (mkClassA (classModule "class-a")) { config = { }; };
          resultB = (mkClassB (classModule "class-b")) { config = { }; };
        in
        {
          classA = resultA.label == "class-a" && resultA.nestedLabel == "class-a";
          classB = resultB.label == "class-b" && resultB.nestedLabel == "class-b";
        };
      expected = {
        classA = true;
        classB = true;
      };
    };

    "test: flake-parts.mkModule is equivalent to mkModule \"flake\"" = {
      expr =
        let
          module =
            {
              closure-lib,
              mkModule,
              ...
            }:
            { config, ... }:
            {
              hasDependencies = builtins.isAttrs closure-lib.caisson.dependencies;
              hasLib = builtins.isAttrs closure-lib;
              nestedOk =
                (mkModule (
                  { ... }:
                  { config, ... }:
                  {
                    ok = true;
                  }
                ))
                  { config = { }; };
            };

          viaAlias = (caisson.flake-parts.mkModule module) { config = { }; };
          viaFactory = ((caisson.mkModule "flake") module) { config = { }; };
        in
        {
          viaAlias = {
            hasDependencies = viaAlias.hasDependencies;
            hasLib = viaAlias.hasLib;
            nestedOk = viaAlias.nestedOk.ok or false;
          };
          viaFactory = {
            hasDependencies = viaFactory.hasDependencies;
            hasLib = viaFactory.hasLib;
            nestedOk = viaFactory.nestedOk.ok or false;
          };
        };
      expected = {
        viaAlias = {
          hasDependencies = true;
          hasLib = true;
          nestedOk = true;
        };
        viaFactory = {
          hasDependencies = true;
          hasLib = true;
          nestedOk = true;
        };
      };
    };
  };

  mkLibOverlay = {
    "test: applies the closure attrset to the overlay" = {
      expr =
        (caisson.mkLibOverlay (
          { closure-lib, ... }:
          {
            overlay = final: prev: {
              hasPkgs = builtins.hasAttr "nixpkgs-lib" closure-lib.caisson.dependencies;
            };
          }
        )).overlay
          { }
          { };
      expected = {
        hasPkgs = true;
      };
    };

    "test: the built overlay is normalized to imports and overlay" = {
      expr = builtins.attrNames (caisson.mkLibOverlay ({ ... }: { overlay = final: prev: { }; }));
      expected = [
        "imports"
        "overlay"
      ];
    };

    "test: closure args can be ignored with an open pattern" = {
      expr = (caisson.mkLibOverlay ({ ... }: { overlay = final: prev: { foo = "bar"; }; })).overlay {
        final = "fake";
      } { prev = "fake"; };
      expected = {
        foo = "bar";
      };
    };

    "test: closure provides a recursive mkLibOverlay" = {
      expr =
        (caisson.mkLibOverlay (
          { mkLibOverlay, ... }:
          {
            overlay = final: prev: { hasMkLibOverlay = builtins.isFunction mkLibOverlay; };
          }
        )).overlay
          { }
          { };
      expected = {
        hasMkLibOverlay = true;
      };
    };

    "test: throws when the body is a bare overlay function" = {
      expr = builtins.tryEval (
        # a body of `final: prev:` without the { overlay } wrapper is an error
        builtins.attrNames (caisson.mkLibOverlay ({ ... }: final: prev: { foo = "bar"; }))
      );
      expected = {
        success = false;
        value = false;
      };
    };

    "test: throws on a bare attrset" = {
      expr = builtins.tryEval ((caisson.mkLibOverlay { foo = "bar"; }).overlay { } { });
      expected = {
        success = false;
        value = false;
      };
    };

    "test: throws on an integer" = {
      expr = builtins.tryEval ((caisson.mkLibOverlay 42) { } { });
      expected = {
        success = false;
        value = false;
      };
    };
  };

  structuredOverlay = {
    "test: structured overlay is applied correctly" = {
      expr =
        let
          myLib = mkTestLib {
            libOverlays = _lib: {
              test = mkLibOverlay (
                { ... }:
                {
                  overlay = final: prev: { structuredVal = "ok"; };
                  imports = [ ];
                }
              );
            };
          };
        in
        myLib.structuredVal or "missing";
      expected = "ok";
    };

    "test: imports are applied before main overlay" = {
      expr =
        let
          myLib = mkTestLib {
            libOverlays = _lib: {
              test = mkLibOverlay (
                { ... }:
                {
                  overlay = final: prev: {
                    sawImport = prev.fromImport or "missing";
                  };
                  imports = [
                    (mkLibOverlay ({ ... }: { overlay = final: prev: { fromImport = "set"; }; }))
                  ];
                }
              );
            };
          };
        in
        myLib.sawImport;
      expected = "set";
    };

    "test: prev.namespace is populated when main overlay runs" = {
      expr =
        let
          myLib = mkTestLib {
            libOverlays = _lib: {
              test = mkLibOverlay (
                { ... }:
                {
                  overlay = final: prev: {
                    myNs = (prev.myNs or { }) // {
                      fromMain = true;
                    };
                  };
                  imports = [
                    (mkLibOverlay (
                      { ... }:
                      {
                        overlay = final: prev: {
                          myNs = {
                            fromImport = true;
                          };
                        };
                      }
                    ))
                  ];
                }
              );
            };
          };
        in
        myLib.myNs;
      expected = {
        fromImport = true;
        fromMain = true;
      };
    };

    "test: nested structured imports" = {
      expr =
        let
          myLib = mkTestLib {
            libOverlays = _lib: {
              test = mkLibOverlay (
                { ... }:
                {
                  overlay = final: prev: {
                    sawDeep = prev.deepVal or "missing";
                  };
                  imports = [
                    (mkLibOverlay (
                      { ... }:
                      {
                        overlay = final: prev: {
                          sawDeeper = prev.deeperVal or "missing";
                        };
                        imports = [
                          (mkLibOverlay ({ ... }: { overlay = final: prev: { deeperVal = "deep"; }; }))
                        ];
                      }
                    ))
                    (mkLibOverlay ({ ... }: { overlay = final: prev: { deepVal = "shallow"; }; }))
                  ];
                }
              );
            };
          };
        in
        {
          sawDeep = myLib.sawDeep;
          sawDeeper = myLib.sawDeeper;
        };
      expected = {
        sawDeep = "shallow";
        sawDeeper = "deep";
      };
    };
  };

  registries = {
    # The registries under `lib.caisson` are read from the manifest of
    # the library, and a lib overlay that writes a registry attribute
    # into the library adds nothing to them.
    "test: the registries are read from the manifest" = {
      expr =
        let
          myLib = mkTestLib {
            modules = testLib: {
              nixos.local = testLib.caisson.mkModule "nixos" ({ ... }: { config.local = true; });
            };
            libOverlays = _lib: {
              writer = mkLibOverlay (
                { mkModule, ... }:
                {
                  imports = [ ];
                  overlay = _final: prev: {
                    caisson-core = prev.caisson-core // {
                      modules.nixos.written = mkModule "nixos" ({ ... }: { });
                    };
                  };
                }
              );
            };
          };
        in
        {
          modules = builtins.attrNames myLib.caisson.modules.nixos;
          # Each module is the module of the manifest's registry, in a
          # module keyed by the name the project that registered it
          # gives it and that project, inside a module keyed by its
          # registry key and that project, here a composition with no
          # name.
          fromManifest =
            builtins.mapAttrs (
              _: builtins.mapAttrs (_: module: builtins.head (builtins.head module.imports).imports)
            ) myLib.caisson.modules == myLib.caisson-core.libManifest.modules
            && myLib.caisson.modules.nixos.local.key == "modules.nixos.local@"
            &&
              (builtins.head myLib.caisson.modules.nixos.local.imports).key == "registered.modules.nixos.local@";
          libOverlays =
            builtins.attrNames myLib.caisson.libOverlays
            == builtins.attrNames myLib.caisson-core.libManifest.libOverlays;
        };
      expected = {
        modules = [ "local" ];
        fromManifest = true;
        libOverlays = true;
      };
    };

    # A project `counter-project` registers `counter`, a module given
    # as a value, with no key. A composition that lists the project
    # reads the entry as `counter-project/counter`, and the library of
    # the project reads it as `counter`. Evaluating a module list that
    # selects the entry from both registries imports the module a single
    # time, so the list it appends to has a single element. The registry keys of the two reads
    # stay as each registry names the entry.
    "test: an entry read from the registry of a composition and from the library of its project is imported once" =
      {
        expr =
          let
            counter =
              { lib, ... }:
              {
                options.counted = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                };
                config.counted = [ "counter" ];
              };
            projectLib = caisson.mkLib {
              dependencies = mockDependencies;
              name = "counter-project";
              modules = _lib: { generic.counter = counter; };
            };
            consumerLib = caisson.mkLib {
              dependencies = mockDependencies;
              name = "consumer";
              projects.counter-project = {
                modules.generic.counter = counter;
              };
            };
            fromConsumer = consumerLib.caisson.modules.generic."counter-project/counter";
            fromProject = projectLib.caisson.modules.generic.counter;
          in
          {
            counted =
              (lib.evalModules {
                modules = [
                  fromConsumer
                  fromProject
                ];
              }).config.counted;
            keys = [
              fromConsumer.key
              fromProject.key
            ];
          };
        expected = {
          counted = [ "counter" ];
          keys = [
            "modules.generic.counter-project/counter@counter-project"
            "modules.generic.counter@counter-project"
          ];
        };
      };

    # Each integration of caisson has the module that declares its
    # configurations option. The evaluation result of a configuration
    # holds configurations of the integrations whose modules the
    # configuration imports.
    "test: an integration has the module that declares its configurations" = {
      expr = {
        key = lib.caisson.nixos.configurationsModule.key;
        declared = lib.caisson.integrations.integrationsIn {
          caisson = {
            nixos = {
              configurations = { };
              exported = { };
            };
            exports.configurations = { };
          };
        };
      };
      expected = {
        key = "caisson-configurations:nixos";
        declared = [ "nixos" ];
      };
    };

    # The parent of a home-manager configuration is the nearest NixOS
    # or nix-darwin configuration above it: of the nearest ancestor of
    # each integration, the ancestor with the most ancestors.
    "test: nearestOf finds the nearest ancestor of the given integrations" = {
      expr =
        let
          outer = {
            name = "outer";
            ancestors = [ "lib" ];
          };
          inner = {
            name = "inner";
            ancestors = [
              "lib"
              "outer"
            ];
          };
          nearestOf = lib.caisson.integrations.nearestOf [
            "nixos"
            "darwin"
          ];
        in
        {
          nearer =
            (nearestOf {
              nearest = {
                nixos = outer;
                darwin = inner;
              };
            }).name;
          nearerFirst =
            (nearestOf {
              nearest = {
                nixos = inner;
                darwin = outer;
              };
            }).name;
          one = (nearestOf { nearest.darwin = outer; }).name;
          other = nearestOf { nearest.structural = inner; };
        };
      expected = {
        nearer = "inner";
        nearerFirst = "inner";
        one = "outer";
        other = null;
      };
    };

    # An entry belongs to the configuration that passes it up, as a
    # reader of the configurations of an integration, when no
    # configuration of that integration sits between the two on the
    # path of the entry. Systems and the configurations of other
    # integrations on the path do not count. The last segment is the
    # entry itself.
    "test: belongsHere stops at the nearest configuration of its integration" = {
      expr =
        let
          segment = type: name: { inherit type name; };
          entry = path: { inherit path; };
          belongs = lib.caisson.integrations.belongsHere "nixos";
        in
        {
          direct = belongs (entry [
            (segment "system" "x86_64-linux")
            (segment "nixos" "node")
          ]);
          insideALayout = belongs (entry [
            (segment "structural" "rack")
            (segment "caisson-disko" "nas-1")
            (segment "system" "x86_64-linux")
            (segment "nixos" "nas-1")
          ]);
          insideANode = belongs (entry [
            (segment "system" "x86_64-linux")
            (segment "nixos" "node")
            (segment "system" "x86_64-linux")
            (segment "nixos" "image")
          ]);
        };
      expected = {
        direct = true;
        insideALayout = true;
        insideANode = false;
      };
    };
  };

  mkLib = {
    "test: bootstraps correctly" = {
      expr =
        let
          myLib = mkTestLib {
            libOverlays = _lib: {
              test = mkLibOverlay (
                { ... }:
                {
                  overlay = final: prev: {
                    composedVal = "ok";
                  };
                }
              );
            };
          };
        in
        myLib.composedVal or "missing";
      expected = "ok";
    };

    "test: multiple overlays compose via prev" = {
      expr =
        let
          myLib = mkTestLib {
            libOverlays = _lib: {
              first = mkLibOverlay ({ ... }: { overlay = final: prev: { fromFirst = "a"; }; });
              second = mkLibOverlay (
                { ... }: { overlay = final: prev: { fromSecond = prev.fromFirst or "missing"; }; }
              );
            };
          };
        in
        myLib.fromSecond;
      expected = "a";
    };

    "test: overlay accesses final for fixpoint" = {
      expr =
        let
          myLib = mkTestLib {
            libOverlays = _lib: {
              first = mkLibOverlay (
                { ... }: { overlay = final: prev: { fromFirst = final.fromSecond or "missing"; }; }
              );
              second = mkLibOverlay ({ ... }: { overlay = final: prev: { fromSecond = "b"; }; });
            };
          };
        in
        myLib.fromFirst;
      expected = "b";
    };

    "test: libOverlayImports filters overlays" = {
      expr =
        let
          myLib = mkTestLib {
            libOverlays = _lib: {
              kept = mkLibOverlay ({ ... }: { overlay = final: prev: { keptVal = "yes"; }; });
              dropped = mkLibOverlay ({ ... }: { overlay = final: prev: { droppedVal = "no"; }; });
            };
            libOverlayImports = lib: [ lib.caisson-core.libManifest.libOverlays.kept ];
          };
        in
        {
          kept = myLib.keptVal or "missing";
          dropped = myLib ? droppedVal;
        };
      expected = {
        kept = "yes";
        dropped = false;
      };
    };

    "test: no local overlays produces valid lib" = {
      expr =
        let
          myLib = mkTestLib { };
        in
        builtins.hasAttr "caisson" myLib;
      expected = true;
    };

    "test: modules function receives final lib with caisson namespace" = {
      expr =
        let
          myLib = caisson.mkLib {
            dependencies = mockDependencies;
            modules = callbackLib: {
              flake = {
                inspect = callbackLib.caisson.flake-parts.mkModule (
                  { ... }:
                  {
                    flake.inspect = {
                      hasNamespace = callbackLib ? caisson;
                      hasMkModule = builtins.isFunction callbackLib.caisson-core.mkModule;
                      hasMkFlakeModule = builtins.isFunction callbackLib.caisson.flake-parts.mkModule;
                      hasMkLibOverlay = builtins.isFunction callbackLib.caisson-core.mkLibOverlay;
                      hasImportApply = builtins.isFunction callbackLib.caisson-core.importApply;
                    };
                  }
                );
              };
            };
          };
          outputs = myLib.caisson.flake-parts.mkTopConfiguration {
            configModule = myLib.caisson.flake-parts.mkModule (
              { ... }:
              {
                systems = [ "x86_64-linux" ];
              }
            );
            moduleImports = modules: [ modules.inspect ];
          };
        in
        outputs.inspect;
      expected = {
        hasNamespace = true;
        hasMkModule = true;
        hasMkFlakeModule = true;
        hasMkLibOverlay = true;
        hasImportApply = true;
      };
    };

    "test: modules function lib has applied local lib overlays" = {
      expr =
        let
          myLib = caisson.mkLib {
            dependencies = mockDependencies;
            libOverlays = _lib: {
              provider = mkLibOverlay (
                { ... }:
                {
                  overlay = _final: _prev: {
                    fromCallbackOverlay = "overlay-visible";
                  };
                }
              );
            };
            modules = callbackLib: {
              flake = {
                inspect = callbackLib.caisson.flake-parts.mkModule (
                  { ... }:
                  {
                    flake.callbackSawOverlay = callbackLib.fromCallbackOverlay or "missing";
                  }
                );
              };
            };
          };
          outputs = myLib.caisson.flake-parts.mkTopConfiguration {
            configModule = myLib.caisson.flake-parts.mkModule (
              { ... }:
              {
                systems = [ "x86_64-linux" ];
              }
            );
            moduleImports = modules: [ modules.inspect ];
          };
        in
        outputs.callbackSawOverlay;
      expected = "overlay-visible";
    };

    "test: modules function lib and returned lib share fixpoint values" = {
      expr =
        let
          myLib = caisson.mkLib {
            dependencies = mockDependencies;
            libOverlays = _lib: {
              marker = mkLibOverlay (
                { ... }:
                {
                  overlay = _final: _prev: {
                    identityMarker = "same-fixpoint";
                  };
                }
              );
            };
            modules = callbackLib: {
              flake = {
                inspect = callbackLib.caisson.flake-parts.mkModule (
                  { ... }:
                  { lib, ... }:
                  {
                    flake.fixpoint = {
                      callbackMarker = callbackLib.identityMarker or "missing";
                      runtimeMarker = lib.identityMarker or "missing";
                    };
                  }
                );
              };
            };
          };
          outputs = myLib.caisson.flake-parts.mkTopConfiguration {
            configModule = myLib.caisson.flake-parts.mkModule (
              { ... }:
              {
                systems = [ "x86_64-linux" ];
              }
            );
            moduleImports = modules: [ modules.inspect ];
          };
        in
        outputs.fixpoint;
      expected = {
        callbackMarker = "same-fixpoint";
        runtimeMarker = "same-fixpoint";
      };
    };

    # The package overlay registry on mkLib (`pkgOverlays`) is the only
    # route for package overlays: the flake-parts option that once held
    # them is not declared, so setting it is the module system's
    # undeclared-option error.
    "test: caisson.nixpkgs.overlays.all is not an option" = {
      expr =
        let
          outputs = lib.caisson.flake-parts.mkTopConfiguration {
            configModule = mkFlakePartsModule (
              { ... }:
              {
                systems = [ "x86_64-linux" ];
                caisson.nixpkgs.overlays.all.legacy =
                  _namespace: _final: _prev:
                  { };
              }
            );
            moduleImports = modules: [ modules.nixpkgs ];
          };
        in
        builtins.deepSeq (builtins.attrNames outputs) true;
      expectedError = {
        type = "ThrownError";
        msg = "The option `caisson\\.nixpkgs\\.overlays' does not exist";
      };
    };

    "test: modules.flake attrset receives working modules in flake-parts.mkTopConfiguration" = {
      expr =
        let
          myLib = mkTestLib {
            modules = _lib: {
              flake =
                let
                  testMod = mkModule "flake" (
                    { ... }:
                    { config, ... }:
                    {
                      options = { };
                    }
                  );
                in
                {
                  test = testMod;
                };
            };
          };
        in
        builtins.hasAttr "caisson" myLib;
      expected = true;
    };

    "test: modules registered via lib aliases work in flake-parts.mkTopConfiguration" = {
      expr =
        let
          myLib = caisson.mkLib {
            dependencies = mockDependencies;
            modules = callbackLib: {
              flake = {
                fromAlias = callbackLib.caisson.flake-parts.mkModule (
                  { ... }:
                  {
                    flake.fromAlias = true;
                  }
                );
              };
            };
          };
          outputs = myLib.caisson.flake-parts.mkTopConfiguration {
            configModule = myLib.caisson.flake-parts.mkModule (
              { ... }:
              {
                systems = [ "x86_64-linux" ];
              }
            );
            moduleImports = modules: [ modules.fromAlias ];
          };
        in
        outputs.fromAlias or false;
      expected = true;
    };

    "test: libOverlays registered via lib aliases work" = {
      expr =
        let
          myLib = caisson.mkLib {
            dependencies = mockDependencies;
            libOverlays = _lib: {
              fromAlias = lib.caisson-core.mkLibOverlay (
                { ... }:
                {
                  overlay = _final: _prev: {
                    overlayViaAlias = true;
                  };
                }
              );
            };
          };
        in
        myLib.overlayViaAlias or false;
      expected = true;
    };

    "test: function-valued libOverlays receives the core lib" = {
      expr =
        let
          myLib = caisson.mkLib {
            dependencies = mockDependencies;
            libOverlays = coreLib: {
              fromFunction = coreLib.caisson-core.mkLibOverlay (
                { ... }:
                {
                  overlay = _final: _prev: {
                    overlayViaFunctionArg = true;
                  };
                }
              );
            };
          };
        in
        myLib.overlayViaFunctionArg or false;
      expected = true;
    };

    "test: function-valued modules receives final composed lib" = {
      expr =
        let
          myLib = caisson.mkLib {
            dependencies = mockDependencies;
            libOverlays = coreLib: {
              marker = coreLib.caisson-core.mkLibOverlay (
                { ... }:
                {
                  overlay = _final: _prev: {
                    functionModulesMarker = "present";
                  };
                }
              );
            };
            modules = runtimeLib: {
              flake = {
                inspect = runtimeLib.caisson.flake-parts.mkModule (
                  { ... }:
                  { lib, ... }:
                  {
                    flake.functionModules = {
                      callbackLib = runtimeLib.functionModulesMarker or "missing";
                      moduleLib = lib.functionModulesMarker or "missing";
                    };
                  }
                );
              };
            };
          };
          outputs = myLib.caisson.flake-parts.mkTopConfiguration {
            configModule = myLib.caisson.flake-parts.mkModule (
              { ... }:
              {
                systems = [ "x86_64-linux" ];
              }
            );
            moduleImports = modules: [ modules.inspect ];
          };
        in
        outputs.functionModules;
      expected = {
        callbackLib = "present";
        moduleLib = "present";
      };
    };

    "test: the builder composes in a library with no nixpkgs library" = {
      # The functions every integration is written from use builtins
      # and the helpers of caisson-core, so composing them alone
      # brings no upstream library and needs no source for one.
      expr =
        let
          myLib = lib.caisson-core.mkLib {
            dependencies = { };
            libOverlays = coreLib: {
              integrations = coreLib.caisson-core.mkLibOverlay (
                inputs.parent.outPath + "/lib-overlays/integrations"
              );
            };
          };
        in
        {
          builder = myLib.caisson.integrations ? mkModuleConfiguration;
          upstream = myLib ? evalModules;
          composed = builtins.filter (key: builtins.match "caisson-core/.*" key == null) (
            builtins.map (entry: entry.key) myLib.caisson-core.libManifest.entries
          );
        };
      expected = {
        builder = true;
        upstream = false;
        composed = [
          "framework"
          "integrations"
        ];
      };
    };

    "test: lib.caisson.mkLib hands every function argument the framework names" = {
      # `libOverlays` and `libOverlayImports` receive a library that
      # holds caisson-core alone; `modules` receives the next stage.
      # Each finds the names of the framework under `lib.caisson`,
      # reading the registry from the manifest of the same library,
      # and the composed library has them too.
      expr =
        let
          seen = stage: given: {
            ${stage} =
              given.caisson ? mkLib
              && builtins.isFunction given.caisson.mkModules
              &&
                builtins.attrNames given.caisson.libOverlays
                == builtins.attrNames given.caisson-core.libManifest.libOverlays;
          };
          myLib = lib.caisson.mkLib {
            dependencies = mockDependencies;
            libOverlays = given: {
              probe = given.caisson.mkLibOverlay (
                { ... }:
                {
                  overlay = _final: _prev: seen "libOverlays" given;
                }
              );
              integrations = given.caisson.mkLibOverlay (inputs.parent.outPath + "/lib-overlays/integrations");
            };
            extraLibOverlayImports = given: [
              {
                imports = [ ];
                overlay = _final: _prev: seen "extraLibOverlayImports" given;
              }
            ];
            modules = given: {
              generic.probe = given.caisson.mkModule "generic" (
                { ... }:
                {
                  config = seen "modules" given;
                }
              );
            };
          };
        in
        {
          inherit (myLib) libOverlays extraLibOverlayImports;
          # The registered module is inside the two modules that key it.
          modules =
            (builtins.head (builtins.head myLib.caisson.modules.generic.probe.imports).imports).config.modules;
          composed =
            builtins.attrNames myLib.caisson.libOverlays
            == builtins.attrNames myLib.caisson-core.libManifest.libOverlays
            && myLib.caisson.libOverlays ? probe;
          malformed =
            (builtins.tryEval (
              lib.caisson.mkLib {
                dependencies = mockDependencies;
                modules = 42;
              }
            )).success;
        };
      expected = {
        libOverlays = true;
        extraLibOverlayImports = true;
        modules = true;
        composed = true;
        malformed = false;
      };
    };

    "test: a registration named nixpkgs-lib replaces the nixpkgs-lib entry" = {
      # The upstream lib is the entry of the `nixpkgs-lib` integration,
      # imported by the key `nixpkgs-lib`; a registration under that
      # name replaces it for every overlay that imports it, the
      # integrations of caisson included.
      expr =
        let
          myLib = caisson.mkLib {
            dependencies = mockDependencies;
            libOverlays = _lib: {
              nixpkgs-lib = mkLibOverlay (
                { ... }:
                {
                  overlay = _final: prev: prev // lib // { customBaseMarker = "from-base"; };
                }
              );
              test = mkLibOverlay (
                { mkLibOverlay, ... }:
                {
                  imports = [
                    (mkLibOverlay (inputs.parent.outPath + "/lib-overlays/nixpkgs-lib") // { key = "nixpkgs-lib"; })
                  ];
                  overlay = final: prev: {
                    sawBase = final.customBaseMarker or "missing";
                  };
                }
              );
            };
          };
        in
        myLib.sawBase;
      expected = "from-base";
    };
  };

  mkExtendedLib = {
    "test: empty overlay list returns base lib unchanged" = {
      expr =
        let
          myLib = mkTestLib { };
        in
        builtins.hasAttr "caisson" myLib && builtins.isAttrs myLib.caisson;
      expected = true;
    };

    "test: overlays applied in order (later sees earlier via prev)" = {
      expr =
        let
          myLib = mkTestLib {
            libOverlays = _lib: {
              aFirst = mkLibOverlay ({ ... }: { overlay = final: prev: { orderA = "first"; }; });
              bSecond = mkLibOverlay (
                { ... }: { overlay = final: prev: { orderB = prev.orderA or "missing"; }; }
              );
            };
          };
        in
        myLib.orderB;
      expected = "first";
    };

    "test: fixpoint via final across overlays" = {
      expr =
        let
          myLib = mkTestLib {
            libOverlays = _lib: {
              aProvider = mkLibOverlay (
                { ... }:
                {
                  overlay = final: prev: {
                    resolved = final.provided or "missing";
                  };
                }
              );
              bProvider = mkLibOverlay ({ ... }: { overlay = final: prev: { provided = "here"; }; });
            };
          };
        in
        myLib.resolved;
      expected = "here";
    };
  };

  flake-parts-mkConfiguration = {
    # The entry point is a pattern function with no `...`: an argument
    # the pattern does not name is Nix's function-argument error,
    # raised before the composition is entered. `tryEval` cannot catch
    # it, so each refusal is an expected error.
    "test: refuses inputs (they belong to mkLib)" = {
      expr = lib.caisson.flake-parts.mkTopConfiguration {
        inputs = { };
        configModule = { };
      };
      expectedError = unexpectedArgument "mkConfiguration" "inputs";
    };

    "test: refuses modules, which configModule and moduleImports give" = {
      expr = lib.caisson.flake-parts.mkTopConfiguration {
        modules = [ ];
        configModule = { };
      };
      expectedError = unexpectedArgument "mkConfiguration" "modules";
    };

    "test: refuses evaluator arguments outside the WithEcosystemArgs variant" = {
      expr = lib.caisson.flake-parts.mkTopConfiguration {
        configModule = { };
        ecosystemArgs = { };
      };
      expectedError = unexpectedArgument "mkConfiguration" "ecosystemArgs";
    };

    "test: filteredArgs strips reserved keys" = {
      # The composed mkFlake call is built from named arguments; this
      # checks the removeAttrs idiom in isolation.
      expr =
        let
          args = {
            configModule = "should-be-removed";
            modules = "should-be-removed";
            moduleImports = "should-be-removed";
            systems = [ "x86_64-linux" ];
            customKey = "should-survive";
          };
          filteredArgs = builtins.removeAttrs args [
            "configModule"
            "modules"
            "moduleImports"
          ];
        in
        {
          hasConfigModule = filteredArgs ? configModule;
          hasModules = filteredArgs ? modules;
          hasModuleImports = filteredArgs ? moduleImports;
          hasSystems = filteredArgs ? systems;
          hasCustomKey = filteredArgs ? customKey;
        };
      expected = {
        hasConfigModule = false;
        hasModules = false;
        hasModuleImports = false;
        hasSystems = true;
        hasCustomKey = true;
      };
    };

    "test: specialArgs merges with user-provided specialArgs" = {
      # flake-parts.mkTopConfiguration merges { lib = final; } with any specialArgs the caller provides.
      expr =
        let
          filteredArgs = {
            specialArgs = {
              userArg = "hello";
            };
          };
          merged = {
            lib = "composed-lib";
          }
          // filteredArgs.specialArgs or { };
        in
        {
          hasLib = merged ? lib;
          hasUserArg = merged ? userArg;
          userArgValue = merged.userArg;
        };
      expected = {
        hasLib = true;
        hasUserArg = true;
        userArgValue = "hello";
      };
    };

    "test: specialArgs defaults when none provided" = {
      expr =
        let
          filteredArgs = { };
          merged = {
            lib = "composed-lib";
          }
          // filteredArgs.specialArgs or { };
        in
        builtins.attrNames merged;
      expected = [ "lib" ];
    };

    "test: the framework module and the default default are selected by name" = {
      # Every entry named `core`, the local entry and the `<project>/core`
      # of a consumed project, is the framework module of the class;
      # every entry named `default` is the default default, what
      # moduleImports selects when omitted.
      expr =
        let
          selection = lib.caisson.integrations;
          registry = {
            core = "c";
            default = "d";
            "dep/core" = "dc";
            "dep/default" = "dd";
            "dep/other" = "do";
            not-default = "n";
            other = "o";
          };
        in
        {
          cores = selection.coreModules registry;
          defaults = selection.defaultModuleImports registry;
        };
      expected = {
        cores = [
          "c"
          "dc"
        ];
        defaults = [
          "d"
          "dd"
        ];
      };
    };

    "test: moduleImports can filter modules" = {
      expr =
        let
          moduleImports = modules: [ modules.a ];
          localModules = {
            a = "mod-a";
            b = "mod-b";
          };
          selected = moduleImports localModules;
        in
        {
          hasA = builtins.elem "mod-a" selected;
          hasB = builtins.elem "mod-b" selected;
        };
      expected = {
        hasA = true;
        hasB = false;
      };
    };

    "test: modules attrset registers flake modules via mkModule" = {
      expr =
        let
          myLib = caisson.mkLib {
            dependencies = mockDependencies;

            modules = _lib: {
              testClass = {
                test = mkModule "test-class" ({ ... }: { config, ... }: { });
              };
              flake = {
                fromModules = mkModule "flake" (
                  { ... }:
                  { config, ... }:
                  {
                    flake.fromModules = true;
                  }
                );
              };
            };
          };

          outputs = myLib.caisson.flake-parts.mkTopConfiguration {
            configModule = myLib.caisson.flake-parts.mkModule (
              { ... }:
              {
                systems = [ "x86_64-linux" ];
              }
            );
            moduleImports = modules: [ modules.fromModules ];
          };
        in
        outputs.fromModules or false;
      expected = true;
    };

    "test: modules attrset alone can register flake modules" = {
      expr =
        let
          myLib = caisson.mkLib {
            dependencies = mockDependencies;

            modules = _lib: {
              flake = {
                fromModulesOnly = mkModule "flake" (
                  { ... }:
                  { config, ... }:
                  {
                    flake.fromModulesOnly = true;
                  }
                );
              };
            };
          };

          outputs = myLib.caisson.flake-parts.mkTopConfiguration {
            configModule = myLib.caisson.flake-parts.mkModule (
              { ... }:
              {
                systems = [ "x86_64-linux" ];
              }
            );
            moduleImports = modules: [ modules.fromModulesOnly ];
          };
        in
        outputs.fromModulesOnly or false;
      expected = true;
    };

    "test: flake-parts.mkTopConfiguration works when modules.flake is absent" = {
      expr =
        let
          myLib = caisson.mkLib {
            dependencies = mockDependencies;
            modules = _lib: {
              testClass = {
                only = mkModule "test-class" ({ ... }: { });
              };
            };
          };
          outputs = myLib.caisson.flake-parts.mkTopConfiguration {
            configModule = myLib.caisson.flake-parts.mkModule (
              { ... }:
              {
                systems = [ "x86_64-linux" ];
              }
            );
          };
        in
        outputs ? checks;
      expected = true;
    };
  };

  errorPaths = {
    "test: mkLibOverlay with null throws" = {
      expr = builtins.tryEval ((caisson.mkLibOverlay null) { } { });
      expected = {
        success = false;
        value = false;
      };
    };

    "test: mkModule with null throws" = {
      # null is not a function taking the closure attrset; plain values must
      # be imported/registered directly, so mkModule rejects them loudly.
      expr = builtins.tryEval (mkFlakePartsModule null);
      expected = {
        success = false;
        value = false;
      };
    };
  };

  types = {
    "test: libOverlay type accepts a built overlay" = {
      expr = lib.caisson-core.types.libOverlay.check (
        mkLibOverlay ({ ... }: { overlay = final: prev: { }; })
      );
      expected = true;
    };

    "test: libOverlay type accepts nested imports" = {
      expr = lib.caisson-core.types.libOverlay.check {
        imports = [
          {
            imports = [ ];
            overlay = final: prev: { };
          }
        ];
        overlay = final: prev: { };
      };
      expected = true;
    };

    "test: libOverlay type rejects a bare overlay function" = {
      expr = lib.caisson-core.types.libOverlay.check (final: prev: { });
      expected = false;
    };

    "test: libOverlay type rejects a malformed import" = {
      expr = lib.caisson-core.types.libOverlay.check {
        imports = [ (final: prev: { }) ];
        overlay = final: prev: { };
      };
      expected = false;
    };

    # `mkIntegration` generates the types of every integration from its
    # name and its class.
    "test: every integration has a module type and a configuration type" = {
      expr = builtins.listToAttrs (
        builtins.map (name: {
          inherit name;
          value = builtins.attrNames lib.caisson.${name}.types;
        }) integrationNames
      );
      expected = builtins.listToAttrs (
        builtins.map (name: {
          inherit name;
          value = [
            "configuration"
            "module"
          ];
        }) integrationNames
      );
    };

    "test: the types name the class and the integration" = {
      expr = {
        module = lib.caisson.home-manager.types.module.description;
        configuration = lib.caisson.home-manager.types.configuration.description;
      };
      expected = {
        module = "module of the class `homeManager`";
        configuration = "home-manager configuration (what `lib.caisson.home-manager.mkConfiguration` returns)";
      };
    };

    # A configuration of nixos-minimal is a nixos configuration, and
    # its modules are of the class nixos.
    "test: an integration over the class of another has the types of the owner" = {
      expr = builtins.mapAttrs (_: type: type.description) lib.caisson.nixos-minimal.types;
      expected = builtins.mapAttrs (_: type: type.description) lib.caisson.nixos.types;
    };

    "test: the module type takes a registered module of its class" = {
      expr = builtins.isAttrs (
        moduleOption lib.caisson.nixos.types.module lib.caisson.modules.nixos.default
      );
      expected = true;
    };

    "test: the module type takes a module that states no class" = {
      expr = builtins.length (moduleOption lib.caisson.nixos.types.module ({ ... }: { })).imports;
      expected = 1;
    };

    "test: the module type refuses a registered module of another class" = {
      expr = moduleOption lib.caisson.nixos.types.module lib.caisson.modules.homeManager.default;
      expectedError = {
        type = "ThrownError";
        msg = "is a module of[[:space:]]+the class `homeManager`, and the option takes a module of the class `nixos`";
      };
    };

    "test: the module type refuses a module whose _class is another" = {
      expr = moduleOption lib.caisson.nixos.types.module { _class = "darwin"; };
      expectedError = {
        type = "ThrownError";
        msg = "the class `darwin`, and the option takes a module of the class `nixos`";
      };
    };

    "test: the configuration type takes what mkConfiguration returns" = {
      expr = lib.caisson.structural.types.configuration.check (
        lib.caisson.structural.mkConfiguration { moduleImports = _modules: [ ]; }
      );
      expected = true;
    };

    "test: the configuration type refuses a value that is not a configuration" = {
      expr = lib.caisson.structural.types.configuration.check { };
      expected = false;
    };
  };

  mkLibArgumentShapes = {
    # mkLib's registration arguments take exactly one shape: a function
    # (`lib: { ... }`). The checks fire as soon
    # as the returned lib is used.
    "test: mkLib throws when modules is an attrset" = {
      expr = builtins.tryEval (builtins.seq (mkTestLib { modules = { }; }) true);
      expected = {
        success = false;
        value = false;
      };
    };

    "test: mkLib throws when libOverlays is an attrset" = {
      expr = builtins.tryEval (builtins.seq (mkTestLib { libOverlays = { }; }) true);
      expected = {
        success = false;
        value = false;
      };
    };
  };

  ecosystemResolution =
    let
      # A minimal terranix "ecosystem": the adapter only needs
      # lib.terranixConfiguration, so a stub shows which source
      # resolution chose.
      terranixStub = probe: {
        lib.terranixConfiguration = evaluatorArgs: {
          stubbed = probe;
          inherit evaluatorArgs;
        };
      };
      # Test compositions register caisson's real terranix integration
      # (built from its source file, like the flake-parts
      # registration) alongside the harness's flake-parts
      # registration. A terranix configuration is evaluated per
      # system the composition declares, here a single system, so a caisson
      # top is the evaluation result for that system: what the stub returns.
      mkResolutionLib =
        extra:
        caisson.mkLib (
          {
            dependencies = mockDependencies;
            systems = [ "x86_64-linux" ];
            libOverlays = _lib: {
              terranix = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/terranix");
            };
          }
          // extra
        );
    in
    {
      "test: a declared ecosystem resolves for an adapter" = {
        expr =
          let
            myLib = mkResolutionLib {
              defaultEcosystemSrc = dependencies: { terranix = terranixStub "declared"; };
            };
          in
          (myLib.caisson.terranix.mkTopConfiguration {
            configModule = { };
          }).stubbed;
        expected = "declared";
      };

      "test: an explicit ecosystemSrc beats the declaration" = {
        expr =
          let
            myLib = mkResolutionLib {
              defaultEcosystemSrc = dependencies: { terranix = terranixStub "declared"; };
            };
          in
          (myLib.caisson.terranix.mkTopConfiguration {
            ecosystemSrc = dependencies: terranixStub "explicit";
            configModule = { };
          }).stubbed;
        expected = "explicit";
      };

      # `ecosystemSrc` selects from the dependencies of the flake, so a
      # configuration gives it as a function; a value is refused before
      # resolution runs.
      "test: an ecosystemSrc given as a value is refused" = {
        expr =
          let
            myLib = mkResolutionLib { };
          in
          (myLib.caisson.terranix.mkTopConfiguration {
            ecosystemSrc = terranixStub "explicit";
            configModule = { };
          }).stubbed;
        expectedError = {
          type = "ThrownError";
          msg = "caisson\\.terranix: `ecosystemSrc` is a function of the dependencies passed to mkLib that\\s+returns the source to use, `ecosystemSrc = dependencies: dependencies\\.<name>;`,\\s+but got a set\\.";
        };
      };

      "test: an input with the exact name is the last place resolution looks" = {
        expr =
          let
            myLib = mkResolutionLib {
              dependencies = mockDependencies // {
                terranix = terranixStub "input";
              };
            };
          in
          (myLib.caisson.terranix.mkTopConfiguration {
            configModule = { };
          }).stubbed;
        expected = "input";
      };

      "test: the declaration beats the exact-name input" = {
        expr =
          let
            myLib = mkResolutionLib {
              dependencies = mockDependencies // {
                terranix = terranixStub "input";
              };
              defaultEcosystemSrc = dependencies: { terranix = terranixStub "declared"; };
            };
          in
          (myLib.caisson.terranix.mkTopConfiguration {
            configModule = { };
          }).stubbed;
        expected = "declared";
      };

      "test: a full miss throws at the adapter" = {
        expr =
          builtins.tryEval
            ((mkResolutionLib { }).caisson.terranix.mkTopConfiguration {
              configModule = { };
            }).stubbed;
        expected = {
          success = false;
          value = false;
        };
      };

      "test: declarations join the manifest" = {
        expr =
          let
            myLib = mkResolutionLib {
              defaultEcosystemSrc = dependencies: { terranix = terranixStub "declared"; };
            };
          in
          (myLib.caisson-core.libManifest.defaultEcosystemSrc.terranix.lib.terranixConfiguration { }).stubbed;
        expected = "declared";
      };
    };

  # The nixos and nixos-minimal integrations: the composed library is
  # the library a NixOS evaluation runs on, threaded into the
  # evaluator of each. The ecosystem source is a stand-in nixpkgs
  # source tree with the files the integrations read,
  # `nixos/lib/eval-config.nix`, `nixos/lib/default.nix` and
  # `nixos/modules/module-list.nix`, each with the signature of the
  # file it stands in for and its treatment of `lib`, including the
  # `import ../../lib` default that imports the library of the source
  # tree. That `lib` directory throws, so evaluating a configuration
  # without a library fails where the evaluator imports a library.
  nixosLib =
    let
      nixosStub = ./nixos-stub;
      # mockDependencies with the nixos stub added, under a name a
      # composition's `defaultEcosystemSrc` selects.
      dependenciesWithNixos = mockDependencies // {
        inherit nixosStub;
      };
      nixosEcosystemSrc = dependencies: {
        nixpkgs = dependencies.nixosStub;
        nixos = dependencies.nixosStub;
      };
      mkComposition =
        extraOverlays:
        caisson.mkLib {
          dependencies = dependenciesWithNixos;
          defaultEcosystemSrc = nixosEcosystemSrc;
          # A configuration takes its system and its package set from
          # the composition.
          systems = [ "x86_64-linux" ];
          pkgSets = stubPkgSets {
            default = {
              marker = "the default set";
            };
            other = {
              marker = "the other set";
            };
          };
          libOverlays =
            _lib:
            {
              nixos = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/nixos");
              nixos-minimal = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/nixos-minimal");
              # The marker this composition adds and nothing else
              # does: reading it inside the evaluation shows which
              # library got there.
              marker = mkLibOverlay (
                { ... }:
                {
                  overlay = _final: _prev: {
                    caissonMarker = "from-the-composition";
                  };
                }
              );
            }
            // extraOverlays;
        };
      myLib = mkComposition { };
      # A composition that declares a single system, a stand-in package
      # config, and a NixOS configuration registered under the name
      # `probe`, which records the name and the system of its
      # evaluation result.
      publishingLib = caisson.mkLib {
        dependencies = dependenciesWithNixos;
        name = "publishing";
        defaultEcosystemSrc = nixosEcosystemSrc;
        systems = [ "x86_64-linux" ];
        pkgSets = stubPkgSets { default = { }; };
        libOverlays = _lib: {
          nixos = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/nixos");
        };
        configs = callbackLib: {
          nixos.probe = callbackLib.caisson.nixos.mkModule (
            { ... }:
            { lib, ... }:
            {
              imports = [ probeModule ];
              seenLib.name = lib.caisson-core.evalManifest.name;
              seenLib.system = lib.caisson-core.evalManifest.system;
            }
          );
        };
      };
      # A configuration module that records what the library the
      # module system handed it contains. It declares the option it
      # sets, the way a NixOS configuration module declares anything
      # the base modules do not, so it reads the same under the
      # minimal evaluator, which takes no base modules.
      probeModule =
        { lib, ... }:
        {
          options.seenLib = lib.mkOption {
            type = lib.types.attrs;
            default = { };
          };
          config.seenLib = {
            # An attribute this composition contributed and nixpkgs
            # does not have: present only if the library the modules
            # run on is the composed library.
            marker = lib.caissonMarker or null;
            # A nixpkgs function, so the composed library is still
            # nixpkgs' library and not a bare marker.
            nixpkgs = lib.isFunction lib.id;
          };
        };
      configuration = myLib.caisson.nixos.mkTopConfiguration {
        configModule = probeModule;
      };
      minimalConfiguration = myLib.caisson.nixos-minimal.mkTopConfiguration {
        configModule = probeModule;
      };
    in
    {
      # The proof that the composed library is passed to the modules of
      # a NixOS configuration: while the configuration is evaluated, a
      # module sees the composition's marker and a nixpkgs function on
      # the same library. `evalModules` builds the `lib` module argument from
      # the library its `lib/modules.nix` closed over, which is
      # the fixpoint the `nixpkgs-lib` entry read rather than what
      # this composition built, so the marker is there only because the
      # composition names `lib` among the special arguments.
      "test: the modules of a nixos configuration see the composed library" = {
        expr = configuration.config.seenLib;
        expected = {
          marker = "from-the-composition";
          nixpkgs = true;
        };
      };

      # The evaluator's `lib` argument, which `eval-config.nix`
      # publishes back as `lib` on the result: the module system, the
      # merging and the type checking of the evaluation all run on it.
      "test: eval-config runs on the composed library" = {
        expr = configuration.libArgument.caissonMarker or null;
        expected = "from-the-composition";
      };

      # The same library is passed to the minimal evaluator, which takes it
      # as the argument of `nixos/lib/default.nix` rather than of
      # `evalModules`.
      "test: the minimal evaluator runs on the composed library" = {
        expr = {
          argument = minimalConfiguration.libArgument.caissonMarker or null;
          modules = minimalConfiguration.config.seenLib;
        };
        expected = {
          argument = "from-the-composition";
          modules = {
            marker = "from-the-composition";
            nixpkgs = true;
          };
        };
      };

      # The minimal evaluator takes no base modules, so the option the
      # module list of the source tree declares is absent from that
      # evaluation, while mkConfigurationFull passes the list
      # explicitly.
      "test: only the full entry point passes the base module list" = {
        expr = {
          minimal = minimalConfiguration.config.stub.fromBaseModules or null;
          full =
            (myLib.caisson.integrations.topValue (
              myLib.caisson-core.finalizeTop (
                myLib.caisson.nixos.mkConfigurationFull {
                  configModule = probeModule;
                }
              )
            )).config.stub.fromBaseModules;
        };
        expected = {
          minimal = null;
          full = true;
        };
      };

      # The `WithEcosystemArgs` variant replaces the library like any
      # evaluator argument, on both entry points: `eval-config.nix`
      # takes `lib` directly, and the minimal evaluator takes it through
      # the import of `nixos/lib`.
      "test: the WithEcosystemArgs variant replaces the library of a nixos evaluation" = {
        expr =
          (myLib.caisson.integrations.topValue (
            myLib.caisson-core.finalizeTop (
              myLib.caisson.nixos.mkConfigurationWithEcosystemArgs {
                configModule = probeModule;
                ecosystemArgs.lib = myLib // {
                  caissonMarker = "from-ecosystemArgs";
                };
              }
            )
          )).libArgument.caissonMarker or null;
        expected = "from-ecosystemArgs";
      };

      "test: the WithEcosystemArgs variant replaces the library of a minimal evaluation" = {
        expr =
          (myLib.caisson.integrations.topValue (
            myLib.caisson-core.finalizeTop (
              myLib.caisson.nixos-minimal.mkConfigurationWithEcosystemArgs {
                configModule = probeModule;
                ecosystemArgs.lib = myLib // {
                  caissonMarker = "from-ecosystemArgs";
                };
              }
            )
          )).libArgument.caissonMarker or null;
        expected = "from-ecosystemArgs";
      };

      # The manifest of a configuration records the arguments it handed
      # to its evaluator as it gave them: the names of the attributes of
      # `specialArgs` and of `ecosystemArgs`, and the file and
      # line number where the configuration gave each. A configuration built
      # by `mkConfiguration` can give `specialArgs`, and a configuration
      # built by the `WithEcosystemArgs` variant can give both. The modules still receive what was
      # given.
      "test: a configuration records the evaluator arguments it gave" =
        let
          manifestOf =
            mkConfiguration: args: (myLib.caisson-core.finalizeTop (mkConfiguration args)).x86_64-linux;
          # The record names this file relative to the source of the
          # unit tests, the flake in `tests/unit`, which holds it.
          positionIn = args: argument: {
            file = "lib-overlays.nix";
            inherit (builtins.unsafeGetAttrPos argument args) line;
          };
          plainArgs = {
            configModule =
              { fromSpecialArgs, ... }:
              {
                imports = [ probeModule ];
                config.seenLib.fromSpecialArgs = fromSpecialArgs;
              };
            specialArgs = {
              fromSpecialArgs = "given";
              unused = _: null;
            };
          };
          withEcosystemArgsArgs = {
            configModule = probeModule;
            specialArgs.fromSpecialArgs = "given";
            ecosystemArgs.lib = myLib // {
              caissonMarker = "from-ecosystemArgs";
            };
          };
          plain = manifestOf myLib.caisson.nixos.mkConfiguration plainArgs;
          withEcosystemArgs = manifestOf myLib.caisson.nixos.mkConfigurationWithEcosystemArgs withEcosystemArgsArgs;
        in
        {
          expr = {
            plain = plain.evaluatorArgs;
            withEcosystemArgs = withEcosystemArgs.evaluatorArgs;
            received = plain.value.config.seenLib.fromSpecialArgs;
          };
          expected = {
            plain.specialArgs = {
              names = [
                "fromSpecialArgs"
                "unused"
              ];
              position = positionIn plainArgs "specialArgs";
            };
            withEcosystemArgs = {
              specialArgs = {
                names = [ "fromSpecialArgs" ];
                position = positionIn withEcosystemArgsArgs "specialArgs";
              };
              ecosystemArgs = {
                names = [ "lib" ];
                position = positionIn withEcosystemArgsArgs "ecosystemArgs";
              };
            };
            received = "given";
          };
        };

      # A configuration that gives neither `specialArgs` nor
      # `ecosystemArgs` records an empty set, on either entry point.
      "test: a configuration without evaluator arguments records none" = {
        expr = {
          plain =
            (myLib.caisson-core.finalizeTop (
              myLib.caisson.nixos.mkConfiguration { configModule = probeModule; }
            )).x86_64-linux.evaluatorArgs;
          withEcosystemArgs =
            (myLib.caisson-core.finalizeTop (
              myLib.caisson.nixos.mkConfigurationWithEcosystemArgs { configModule = probeModule; }
            )).x86_64-linux.evaluatorArgs;
        };
        expected = {
          plain = { };
          withEcosystemArgs = { };
        };
      };

      # A NixOS configuration takes its package set from the
      # composition, for the system the composition declares: the set
      # the `defaultPkgs` argument selects from the available sets, and
      # the set named `default` when nothing selects. Each available
      # set is still passed to the modules by config name, as the
      # `pkgSets` special argument, whichever is selected.
      "test: a nixos configuration selects its package set when it is constructed" = {
        expr =
          let
            selecting =
              defaultPkgs:
              (myLib.caisson.nixos.mkTopConfiguration {
                inherit defaultPkgs;
                configModule =
                  { pkgSets, ... }:
                  {
                    imports = [ probeModule ];
                    config.seenLib.byName = builtins.mapAttrs (_: set: set.marker) pkgSets;
                  };
              }).config;
            other = selecting (pkgSets: pkgSets.other);
          in
          {
            default = configuration.config.nixpkgs.pkgs.marker;
            other = other.nixpkgs.pkgs.marker;
            byName = other.seenLib.byName;
            system = configuration.config.stub.system;
            minimal = minimalConfiguration._module.args.pkgs.marker;
            minimalOther =
              (myLib.caisson.nixos-minimal.mkTopConfiguration {
                defaultPkgs = pkgSets: pkgSets.other;
                configModule = { ... }: { };
              })._module.args.pkgs.marker;
          };
        expected = {
          default = "the default set";
          other = "the other set";
          byName = {
            default = "the default set";
            other = "the other set";
          };
          system = "x86_64-linux";
          minimal = "the default set";
          minimalOther = "the other set";
        };
      };

      # A selection holds for the configurations declared inside the
      # configuration that makes it: a configuration that selects
      # nothing runs on what the nearest configuration above it
      # selected, through levels of any integration, and a
      # configuration declared inside it selects another for itself and
      # the configurations declared inside it. Beside the configuration
      # that makes the selection nothing selects, and a configuration
      # runs on the set named `default`.
      "test: a package set selection holds inside the configuration that makes it" = {
        expr =
          let
            nixosConfiguration =
              lib: args:
              lib.caisson.nixos.mkConfiguration (
                {
                  configModule = { ... }: { };
                }
                // args
              );
            top = myLib.caisson-core.finalizeTop (
              myLib.caisson.structural.mkConfiguration {
                moduleImports = _modules: [ ];
                configModule =
                  { lib, ... }:
                  {
                    caisson.nixos.configurations.beside = nixosConfiguration lib { };
                    caisson.structural.configurations.group = lib.caisson.structural.mkConfiguration {
                      moduleImports = _modules: [ ];
                      defaultPkgs = pkgSets: pkgSets.other;
                      configModule =
                        { lib, ... }:
                        {
                          caisson.nixos.configurations.inherits = nixosConfiguration lib {
                            configModule =
                              { lib, ... }:
                              {
                                caisson.nixos.configurations.image = nixosConfiguration lib { };
                              };
                          };
                          caisson.nixos.configurations.selects = nixosConfiguration lib {
                            defaultPkgs = pkgSets: pkgSets.default;
                            configModule =
                              { lib, ... }:
                              {
                                caisson.nixos.configurations.image = nixosConfiguration lib { };
                              };
                          };
                        };
                    };
                  };
              }
            );
            nixosConfigurationsIn = manifest: manifest.children.system.x86_64-linux.children.nixos;
            setOf = manifest: manifest.value.config.nixpkgs.pkgs.marker;
            grouped = nixosConfigurationsIn top.children.structural.group;
          in
          {
            beside = setOf (nixosConfigurationsIn top).beside;
            inherits = setOf grouped.inherits;
            insideInherits = setOf (nixosConfigurationsIn grouped.inherits).image;
            selects = setOf grouped.selects;
            insideSelects = setOf (nixosConfigurationsIn grouped.selects).image;
          };
        expected = {
          beside = "the default set";
          inherits = "the other set";
          insideInherits = "the other set";
          selects = "the default set";
          insideSelects = "the default set";
        };
      };

      # A module of a configuration selects the package set of the
      # configurations declared inside it
      # (`caisson.forChildren.defaultPkgs`). The configuration itself
      # runs on the set it was constructed with, and a configuration
      # declared inside it that is constructed with a selection runs on
      # that selection.
      "test: a configuration selects the package set of the configurations declared inside it" = {
        expr =
          let
            nixosConfiguration =
              lib: args:
              lib.caisson.nixos.mkConfiguration (
                {
                  configModule = { ... }: { };
                }
                // args
              );
            parent =
              (myLib.caisson-core.finalizeTop (
                nixosConfiguration myLib {
                  configModule =
                    { lib, ... }:
                    {
                      caisson.forChildren.defaultPkgs = pkgSets: pkgSets.other;
                      caisson.nixos.configurations.image = nixosConfiguration lib {
                        configModule =
                          { lib, ... }:
                          {
                            caisson.nixos.configurations.nested = nixosConfiguration lib { };
                          };
                      };
                      caisson.nixos.configurations.selects = nixosConfiguration lib {
                        defaultPkgs = pkgSets: pkgSets.default;
                      };
                    };
                }
              )).x86_64-linux;
            nixosConfigurationsIn = manifest: manifest.children.system.x86_64-linux.children.nixos;
            setOf = manifest: manifest.value.config.nixpkgs.pkgs.marker;
          in
          {
            parent = setOf parent;
            image = setOf (nixosConfigurationsIn parent).image;
            nested = setOf (nixosConfigurationsIn (nixosConfigurationsIn parent).image).nested;
            selects = setOf (nixosConfigurationsIn parent).selects;
          };
        expected = {
          parent = "the default set";
          image = "the other set";
          nested = "the other set";
          selects = "the default set";
        };
      };

      # Each configuration evaluated per system records which package
      # config it runs on and the configuration that made the
      # selection: its `defaultPkgs`, the `defaultPkgs` of a
      # configuration above it, or the `caisson.forChildren.defaultPkgs`
      # of a parent. Where nothing selects it records `default` and no
      # level. It also records the names of the namespaces of its lib.
      "test: a configuration records the package config it runs on and who selected it" = {
        expr =
          let
            nixosConfiguration =
              lib: args:
              lib.caisson.nixos.mkConfiguration (
                {
                  configModule = { ... }: { };
                }
                // args
              );
            top = myLib.caisson-core.finalizeTop (
              myLib.caisson.structural.mkConfiguration {
                moduleImports = _modules: [ ];
                configModule =
                  { lib, ... }:
                  {
                    caisson.nixos.configurations.beside = nixosConfiguration lib { };
                    caisson.structural.configurations.group = lib.caisson.structural.mkConfiguration {
                      moduleImports = _modules: [ ];
                      defaultPkgs = pkgSets: pkgSets.other;
                      configModule =
                        { lib, ... }:
                        {
                          caisson.nixos.configurations.inherits = nixosConfiguration lib { };
                          caisson.nixos.configurations.selects = nixosConfiguration lib {
                            defaultPkgs = pkgSets: pkgSets.default;
                            configModule =
                              { lib, ... }:
                              {
                                caisson.nixos.configurations.image = nixosConfiguration lib { };
                              };
                          };
                        };
                    };
                  };
              }
            );
            parent =
              (myLib.caisson-core.finalizeTop (
                nixosConfiguration myLib {
                  configModule =
                    { lib, ... }:
                    {
                      caisson.forChildren.defaultPkgs = pkgSets: pkgSets.other;
                      caisson.nixos.configurations.image = nixosConfiguration lib { };
                    };
                }
              )).x86_64-linux;
            nixosConfigurationsIn = manifest: manifest.children.system.x86_64-linux.children.nixos;
            grouped = nixosConfigurationsIn top.children.structural.group;
            beside = (nixosConfigurationsIn top).beside;
          in
          {
            beside = beside.pkgSet;
            inherits = grouped.inherits.pkgSet;
            selects = grouped.selects.pkgSet;
            insideSelects = (nixosConfigurationsIn grouped.selects).image.pkgSet;
            parent = parent.pkgSet;
            image = (nixosConfigurationsIn parent).image.pkgSet;
            namespaces =
              builtins.elem "mkConfiguration" beside.namespaces.caisson.nixos
              && builtins.elem "namePathOf" beside.namespaces.caisson-core;
          };
        expected =
          let
            group = {
              type = "structural";
              name = "group";
            };
            selectsPath = [
              group
              {
                type = "system";
                name = "x86_64-linux";
              }
              {
                type = "nixos";
                name = "selects";
              }
            ];
          in
          {
            beside = {
              name = "default";
              level = null;
            };
            inherits = {
              name = "other";
              level = [ group ];
            };
            selects = {
              name = "default";
              level = selectsPath;
            };
            insideSelects = {
              name = "default";
              level = selectsPath;
            };
            parent = {
              name = "default";
              level = null;
            };
            image = {
              name = "other";
              level = [ ];
            };
            namespaces = true;
          };
      };

      # Where no configuration from the caisson top down selects, a
      # configuration runs on the set named `default`, and a
      # composition that declares none says so, with the sets it does
      # declare.
      "test: a configuration with no default package set and no selection is refused" = {
        expr =
          let
            noDefault = caisson.mkLib {
              dependencies = dependenciesWithNixos;
              name = "no-default";
              defaultEcosystemSrc = nixosEcosystemSrc;
              systems = [ "x86_64-linux" ];
              pkgSets = stubPkgSets { stable = { }; };
              libOverlays = _lib: {
                nixos = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/nixos");
              };
            };
          in
          (noDefault.caisson.nixos.mkTopConfiguration {
            configModule = { ... }: { };
          }).config.nixpkgs.pkgs;
        expectedError = {
          type = "ThrownError";
          msg = "runs on the package set named `default`,\\s+since no configuration from the caisson top down to it selects one, and the\\s+package sets available here are stable";
        };
      };

      # The same argument selects what a flake's perSystem runs on.
      "test: a flake selects the package set of perSystem when it is constructed" = {
        expr =
          let
            pkgsOf =
              args:
              (myLib.caisson-core.finalizeTop (
                myLib.caisson.flake-parts.mkConfiguration (
                  args
                  // {
                    moduleImports = _modules: [ ];
                    configModule = {
                      systems = [ "x86_64-linux" ];
                      perSystem =
                        { pkgs, ... }:
                        {
                          legacyPackages.marker = pkgs.marker;
                        };
                    };
                  }
                )
              )).outputs.flake.legacyPackages.x86_64-linux.marker;
          in
          {
            default = pkgsOf { };
            other = pkgsOf { defaultPkgs = pkgSets: pkgSets.other; };
          };
        expected = {
          default = "the default set";
          other = "the other set";
        };
      };

      # A NixOS configuration declared at the caisson top has an evaluation
      # result for each system the composition declares: finalizing it
      # gives its evaluation results by system, also when that is a
      # single system, and none when the composition declares no system.
      # A caisson top read as a tool reads it is the evaluation result where
      # there is a single system, and the evaluation results by system
      # where there are several.
      "test: a nixos configuration has an evaluation result for each system the composition declares" = {
        expr =
          let
            on =
              systems:
              caisson.mkLib {
                dependencies = dependenciesWithNixos;
                name = "probe";
                defaultEcosystemSrc = nixosEcosystemSrc;
                inherit systems;
                libOverlays = _lib: {
                  nixos = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/nixos");
                };
              };
            evaluationResultsOn =
              systems:
              let
                composed = on systems;
              in
              composed.caisson-core.finalizeTop (
                composed.caisson.nixos.mkConfiguration { configModule = probeModule; }
              );
            topOn = systems: (on systems).caisson.nixos.mkTopConfiguration { configModule = probeModule; };
            several = [
              "x86_64-linux"
              "aarch64-linux"
            ];
            x86 = (evaluationResultsOn several).x86_64-linux;
          in
          {
            none = builtins.attrNames (evaluationResultsOn null);
            empty = builtins.attrNames (evaluationResultsOn [ ]);
            single = builtins.attrNames (evaluationResultsOn [ "x86_64-linux" ]);
            several = builtins.mapAttrs (_: result: result.value.config.stub.system) (
              evaluationResultsOn several
            );
            name = x86.name;
            above = {
              inherit (x86.parent) type name;
            };
            topOfNone = topOn null;
            topOfSingle = (topOn [ "x86_64-linux" ]).config.stub.system;
            topOfSeveral = builtins.mapAttrs (_: evaluated: evaluated.config.stub.system) (topOn several);
          };
        expected = {
          none = [ ];
          empty = [ ];
          single = [ "x86_64-linux" ];
          several = {
            aarch64-linux = "aarch64-linux";
            x86_64-linux = "x86_64-linux";
          };
          name = "probe";
          above = {
            type = "system";
            name = "x86_64-linux";
          };
          topOfNone = { };
          topOfSingle = "x86_64-linux";
          topOfSeveral = {
            aarch64-linux = "aarch64-linux";
            x86_64-linux = "x86_64-linux";
          };
        };
      };

      # A configuration declared under the option of another
      # integration is refused, with the option it belongs under.
      "test: a configuration declared under another integration's option is refused" = {
        expr =
          (publishingLib.caisson.structural.mkTopConfiguration {
            moduleImports = _modules: [ ];
            configModule =
              { lib, ... }:
              {
                caisson.nixos.configurations.inner = lib.caisson.structural.mkConfiguration {
                  moduleImports = _modules: [ ];
                };
              };
          }).caisson.manifest.children;
        expectedError = {
          type = "ThrownError";
          msg = "Declare it under `caisson\\.structural\\.configurations`";
        };
      };

      # In the tree of manifests a configuration of the minimal evaluator is a NixOS
      # configuration: it is declared where NixOS configurations are,
      # has their type, and is published with them.
      "test: a nixos-minimal configuration is declared and published as a nixos configuration" = {
        expr =
          let
            minimalLib = caisson.mkLib {
              dependencies = dependenciesWithNixos;
              name = "publishing";
              defaultEcosystemSrc = nixosEcosystemSrc;
              systems = [ "x86_64-linux" ];
              pkgSets = stubPkgSets { default = { }; };
              libOverlays = _lib: {
                nixos = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/nixos");
                nixos-minimal = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/nixos-minimal");
              };
            };
            top = minimalLib.caisson.structural.mkTopConfiguration {
              moduleImports = _modules: [ ];
              configModule =
                { lib, ... }:
                {
                  caisson.nixos.configurations.small = lib.caisson.nixos-minimal.mkConfiguration {
                    configModule = { ... }: { };
                  };
                };
            };
            small = top.caisson.manifest.children.system.x86_64-linux.children.nixos.small;
          in
          {
            type = small.type;
            published = builtins.attrNames top.nixosConfigurations;
            # The minimal evaluator ran: its evaluation result has no `system.build`.
            minimal = !(top.nixosConfigurations.small.config ? system);
          };
        expected = {
          type = "nixos";
          published = [ "small" ];
          minimal = true;
        };
      };

      # A NixOS configuration declared inside another configuration is
      # finalized under the attribute it is declared under, and takes
      # the configuration registered under that name when it passes no
      # module. In the tree of manifests its evaluation result sits
      # under its name, inside the system, inside the configuration that
      # declares it.
      "test: a nixos configuration is declared inside a configuration and found by name" = {
        expr =
          let
            top = publishingLib.caisson-core.finalizeTop (
              publishingLib.caisson.structural.mkConfiguration {
                moduleImports = _modules: [ ];
                configModule =
                  { lib, ... }:
                  {
                    caisson.nixos.configurations.probe = lib.caisson.nixos.mkConfiguration { };
                  };
              }
            );
            system = top.children.system.x86_64-linux;
            probe = system.children.nixos.probe;
          in
          {
            children = builtins.attrNames top.children;
            systems = builtins.attrNames top.children.system;
            systemType = system.type;
            type = probe.type;
            name = probe.value.config.seenLib.name;
            seenSystem = probe.value.config.seenLib.system;
            ancestors = builtins.map (ancestor: ancestor.type) probe.ancestors;
            nearest = builtins.attrNames probe.nearest;
            outputs = builtins.attrNames probe.outputs;
          };
        expected = {
          children = [ "system" ];
          systems = [ "x86_64-linux" ];
          systemType = "system";
          type = "nixos";
          name = "probe";
          seenSystem = "x86_64-linux";
          ancestors = [
            "lib"
            "structural"
            "system"
          ];
          nearest = [
            "structural"
            "system"
          ];
          outputs = [
            "checks"
            "exports"
            "images"
            "toplevel"
            "vm"
            "vmWithBootLoader"
          ];
        };
      };

      # A configuration of any integration holds configurations of any
      # integration declared inside it. The same module, declaring a
      # configuration of each integration, is the module of a parent of
      # each integration, and each parent holds each of them.
      "test: a configuration of any integration holds configurations of any integration" = {
        expr =
          let
            children =
              { lib, ... }:
              {
                caisson.structural.configurations.group = lib.caisson.structural.mkConfiguration {
                  moduleImports = _modules: [ ];
                };
                caisson.flake-parts.configurations.flake = lib.caisson.flake-parts.mkConfiguration {
                  moduleImports = _modules: [ ];
                };
                caisson.nixos.configurations.full = lib.caisson.nixos.mkConfiguration {
                  configModule = { ... }: { };
                };
                caisson.nixos.configurations.small = lib.caisson.nixos-minimal.mkConfiguration {
                  configModule = { ... }: { };
                };
              };
            everyLib = caisson.mkLib {
              dependencies = dependenciesWithNixos;
              name = "publishing";
              defaultEcosystemSrc = nixosEcosystemSrc;
              systems = [ "x86_64-linux" ];
              pkgSets = stubPkgSets { default = { }; };
              libOverlays = _lib: {
                nixos = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/nixos");
                nixos-minimal = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/nixos-minimal");
              };
            };
            top = everyLib.caisson-core.finalizeTop (
              everyLib.caisson.structural.mkConfiguration {
                moduleImports = _modules: [ ];
                configModule =
                  { lib, ... }:
                  {
                    caisson.structural.configurations.parent = lib.caisson.structural.mkConfiguration {
                      moduleImports = _modules: [ ];
                      configModule = children;
                    };
                    caisson.flake-parts.configurations.parent = lib.caisson.flake-parts.mkConfiguration {
                      moduleImports = _modules: [ ];
                      configModule = children;
                    };
                    caisson.nixos.configurations.parent = lib.caisson.nixos.mkConfiguration {
                      configModule = children;
                    };
                    caisson.nixos.configurations.smallParent = lib.caisson.nixos-minimal.mkConfiguration {
                      configModule = children;
                    };
                  };
              }
            );
            held = parent: {
              direct = builtins.mapAttrs (_: builtins.attrNames) (
                builtins.removeAttrs parent.children [ "system" ]
              );
              atSystem = builtins.mapAttrs (_: builtins.attrNames) parent.children.system.x86_64-linux.children;
              # The configurations declared inside have finished
              # evaluation results.
              fullIsNixos = parent.children.system.x86_64-linux.children.nixos.full.value ? config;
            };
            nixosConfigurations = top.children.system.x86_64-linux.children.nixos;
          in
          {
            structural = held top.children.structural.parent;
            flake-parts = held top.children.flake-parts.parent;
            nixos = held nixosConfigurations.parent;
            nixos-minimal = held nixosConfigurations.smallParent;
          };
        expected =
          let
            everything = {
              direct = {
                flake-parts = [ "flake" ];
                structural = [ "group" ];
              };
              atSystem = {
                nixos = [
                  "full"
                  "small"
                ];
              };
              fullIsNixos = true;
            };
          in
          {
            structural = everything;
            flake-parts = everything;
            nixos = everything;
            nixos-minimal = everything;
          };
      };

      # A configuration adds registered modules to the default selection
      # of a class for the configurations declared inside it. A
      # configuration of that class that passes no `moduleImports` gets
      # the additions when it is declared inside, also several levels
      # down and through levels of other integrations, and the
      # configuration that adds them does not get them. A level declared
      # inside adds after the levels above. The module registry is the
      # registry of the composition at each level.
      "test: a configuration adds to the default modules of the configurations inside it" = {
        expr =
          let
            # The option the test modules define into, keyed so that a
            # configuration importing several of them declares it
            # once.
            notesOption = {
              key = "test-notes-option";
              imports = [
                (
                  { lib, ... }:
                  {
                    options.notes = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      default = [ ];
                    };
                  }
                )
              ];
            };
            noted = note: {
              imports = [ notesOption ];
              config.notes = [ note ];
            };
            # The modules are registered in the composition. A
            # configuration selects from that registry.
            registeringModulesLib = caisson.mkLib {
              dependencies = dependenciesWithNixos;
              name = "registering-modules";
              defaultEcosystemSrc = nixosEcosystemSrc;
              systems = [ "x86_64-linux" ];
              pkgSets = stubPkgSets { default = { }; };
              libOverlays = _lib: {
                nixos = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/nixos");
              };
              modules = lib: {
                nixos = {
                  site = lib.caisson.nixos.mkModule ({ ... }: noted "site");
                  spare = lib.caisson.nixos.mkModule ({ ... }: noted "spare");
                  rack-site = lib.caisson.nixos.mkModule ({ ... }: noted "rack site");
                };
                structural.site = lib.caisson.structural.mkModule ({ ... }: noted "structural site");
              };
            };
            top = registeringModulesLib.caisson-core.finalizeTop (
              registeringModulesLib.caisson.structural.mkConfiguration {
                moduleImports = _modules: [ ];
                configModule =
                  { lib, ... }:
                  {
                    imports = [ (noted "top") ];
                    caisson.forChildren.extraDefaultModuleImports.nixos = lib: [ lib.caisson.modules.nixos.site ];
                    caisson.forChildren.extraDefaultModuleImports.structural = lib: [
                      lib.caisson.modules.structural.site
                    ];
                    caisson.nixos.configurations.direct = lib.caisson.nixos.mkConfiguration {
                      configModule = { ... }: { };
                    };
                    caisson.nixos.configurations.chosen = lib.caisson.nixos.mkConfiguration {
                      configModule = { ... }: { };
                      moduleImports = modules: [ modules.spare ];
                    };
                    # `extraModuleImports` adds to the default, which
                    # `moduleImports` replaces.
                    caisson.nixos.configurations.added = lib.caisson.nixos.mkConfiguration {
                      configModule = { ... }: { };
                      extraModuleImports = modules: [ modules.spare ];
                    };
                    caisson.structural.configurations.rack = lib.caisson.structural.mkConfiguration {
                      configModule =
                        { lib, ... }:
                        {
                          caisson.forChildren.extraDefaultModuleImports.nixos = lib: [
                            lib.caisson.modules.nixos.rack-site
                          ];
                          caisson.nixos.configurations.deep = lib.caisson.nixos.mkConfiguration {
                            configModule = { ... }: { };
                          };
                        };
                    };
                  };
              }
            );
            nixosConfigurations = top.children.system.x86_64-linux.children.nixos;
            rack = top.children.structural.rack;
            deep = rack.children.system.x86_64-linux.children.nixos.deep;
          in
          {
            top = top.value.config.notes;
            direct = nixosConfigurations.direct.value.config.notes;
            chosen = nixosConfigurations.chosen.value.config.notes;
            added = builtins.sort builtins.lessThan nixosConfigurations.added.value.config.notes;
            rack = rack.value.config.notes;
            deep = builtins.sort builtins.lessThan deep.value.config.notes;
            sameRegistryInside =
              builtins.attrNames nixosConfigurations.direct.modules.nixos == builtins.attrNames top.modules.nixos;
          };
        expected = {
          top = [ "top" ];
          direct = [ "site" ];
          chosen = [ "spare" ];
          added = [
            "site"
            "spare"
          ];
          rack = [ "structural site" ];
          deep = [
            "rack site"
            "site"
          ];
          sameRegistryInside = true;
        };
      };

      # A configuration is passed up to the caisson top through each level
      # above it, whatever their integrations: each level passes up what
      # is declared inside it. Here a NixOS configuration is declared
      # inside a NixOS configuration, inside a structural configuration,
      # inside a flake-parts configuration, and the modules of those
      # levels declare configurations and nothing else.
      "test: a configuration is published through levels of any integration" = {
        expr =
          let
            top = publishingLib.caisson.structural.mkTopConfiguration {
              moduleImports = _modules: [ ];
              configModule =
                { lib, ... }:
                {
                  caisson.flake-parts.configurations.site = lib.caisson.flake-parts.mkConfiguration {
                    moduleImports = _modules: [ ];
                    configModule =
                      { lib, ... }:
                      {
                        caisson.structural.configurations.rack = lib.caisson.structural.mkConfiguration {
                          moduleImports = _modules: [ ];
                          configModule =
                            { lib, ... }:
                            {
                              caisson.nixos.configurations.server = lib.caisson.nixos.mkConfiguration {
                                configModule =
                                  { lib, ... }:
                                  {
                                    caisson.nixos.configurations.image = lib.caisson.nixos.mkConfiguration {
                                      configModule = { ... }: { };
                                    };
                                  };
                              };
                            };
                        };
                      };
                  };
                };
            };
            image =
              top.caisson.manifest.children.flake-parts.site.children.structural.rack.children.system.x86_64-linux.children.nixos.server.children.system.x86_64-linux.children.nixos.image;
          in
          {
            published = builtins.attrNames top.nixosConfigurations;
            # What is published is the evaluation result in the tree of
            # manifests.
            same = top.nixosConfigurations.image == image.value;
            above = builtins.map (ancestor: ancestor.type) image.ancestors;
          };
        expected = {
          published = [
            "image"
            "server"
          ];
          same = true;
          above = [
            "lib"
            "structural"
            "flake-parts"
            "structural"
            "system"
            "nixos"
            "system"
          ];
        };
      };

      # The configurations declared inside a NixOS configuration, in the
      # tree of manifests and at a caisson top: they are in its manifest, under
      # their system where they are evaluated per system, they see it as
      # the nearest NixOS configuration, and a caisson top publishes them with
      # the others.
      "test: a nixos configuration holds configurations declared inside it" = {
        expr =
          let
            top = publishingLib.caisson.structural.mkTopConfiguration {
              moduleImports = _modules: [ ];
              configModule =
                { lib, ... }:
                {
                  caisson.nixos.configurations.server = lib.caisson.nixos.mkConfiguration {
                    configModule =
                      { lib, ... }:
                      {
                        imports = [ probeModule ];
                        caisson.nixos.configurations.image = lib.caisson.nixos.mkConfiguration {
                          configModule =
                            { ... }:
                            {
                              imports = [ probeModule ];
                            };
                        };
                        caisson.structural.configurations.group = lib.caisson.structural.mkConfiguration {
                          moduleImports = _modules: [ ];
                        };
                      };
                  };
                };
            };
            server = top.caisson.manifest.children.system.x86_64-linux.children.nixos.server;
            image = server.children.system.x86_64-linux.children.nixos.image;
          in
          {
            children = builtins.attrNames server.children;
            group = server.children.structural.group.type;
            imageName = image.name;
            imageEvaluates = image.value.config.seenLib ? marker;
            imageNearest = image.nearest.nixos.name;
            imageAncestors = builtins.map (ancestor: ancestor.type) image.ancestors;
            published = builtins.attrNames top.nixosConfigurations;
          };
        expected = {
          children = [
            "structural"
            "system"
          ];
          group = "structural";
          imageName = "image";
          imageEvaluates = true;
          imageNearest = "server";
          imageAncestors = [
            "lib"
            "structural"
            "system"
            "nixos"
            "system"
          ];
          published = [
            "image"
            "server"
          ];
        };
      };

      # What a caisson top publishes: the NixOS configurations declared inside
      # it, nested ones included, as `nixosConfigurations.<name>`, each
      # the evaluated configuration. The names come from the paths: a
      # name that is alone stays bare, with the system above it and the
      # structural configuration it sits in left out, and the same
      # name in several structural configurations gains their names.
      "test: a caisson top publishes the nixos configurations inside it under names from their paths" = {
        expr =
          let
            nixosConfigurationNamed =
              lib: name:
              lib.caisson.nixos.mkConfiguration {
                configModule = {
                  imports = [ probeModule ];
                  seenLib.name = name;
                };
              };
            group =
              lib: names:
              lib.caisson.structural.mkConfiguration {
                moduleImports = _modules: [ ];
                configModule =
                  { lib, ... }:
                  {
                    caisson.nixos.configurations = lib.genAttrs names (nixosConfigurationNamed lib);
                  };
              };
            declarations =
              { lib, ... }:
              {
                caisson.nixos.configurations.direct = nixosConfigurationNamed lib "direct";
                caisson.structural.configurations.a = group lib [
                  "host-1"
                  "host-2"
                ];
                caisson.structural.configurations.b = group lib [ "host-1" ];
              };
            structuralTop = publishingLib.caisson.structural.mkTopConfiguration {
              moduleImports = _modules: [ ];
              configModule = declarations;
            };
            flakeTop = publishingLib.caisson.flake-parts.mkTopConfiguration {
              moduleImports = _modules: [ ];
              configModule = {
                imports = [ declarations ];
              };
            };
          in
          {
            structural = builtins.attrNames structuralTop.nixosConfigurations;
            flake = builtins.attrNames flakeTop.nixosConfigurations;
            evaluated = structuralTop.nixosConfigurations."a/host-1".config.stub.system;
            keepsTheRegistries = structuralTop ? libOverlays && !(structuralTop ? configurations);
          };
        expected = {
          structural = [
            "a/host-1"
            "b/host-1"
            "direct"
            "host-2"
          ];
          flake = [
            "a/host-1"
            "b/host-1"
            "direct"
            "host-2"
          ];
          evaluated = "x86_64-linux";
          keepsTheRegistries = true;
        };
      };

      # Where the composition declares several systems, a name is
      # published for each evaluation result, told apart by the system.
      # `exported` selects what is passed up, and what it leaves out is
      # not published.
      "test: a caisson top publishes an evaluation result per system, and only what is selected" = {
        expr =
          let
            severalLib = caisson.mkLib {
              dependencies = dependenciesWithNixos;
              name = "several";
              defaultEcosystemSrc = nixosEcosystemSrc;
              systems = [
                "x86_64-linux"
                "aarch64-linux"
              ];
              libOverlays = _lib: {
                nixos = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/nixos");
              };
            };
            top =
              exported:
              severalLib.caisson.structural.mkTopConfiguration {
                moduleImports = _modules: [ ];
                configModule =
                  { lib, ... }:
                  {
                    caisson.nixos.configurations.probe = lib.caisson.nixos.mkConfiguration {
                      configModule = probeModule;
                    };
                    caisson.nixos.exported = exported;
                  };
              };
          in
          {
            all = builtins.attrNames (top (configurations: configurations)).nixosConfigurations;
            none = (top (_configurations: { })) ? nixosConfigurations;
          };
        expected = {
          all = [
            "aarch64-linux/probe"
            "x86_64-linux/probe"
          ];
          none = false;
        };
      };

      # `exported` returns the configurations to pass up, by the name
      # each is passed up under. A selector that returns a
      # configuration under another name publishes it under that name.
      "test: a selector that renames a configuration publishes it under the new name" = {
        expr =
          let
            oneSystemLib = caisson.mkLib {
              dependencies = dependenciesWithNixos;
              name = "one-system";
              defaultEcosystemSrc = nixosEcosystemSrc;
              systems = [ "x86_64-linux" ];
              libOverlays = _lib: {
                nixos = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/nixos");
              };
            };
            top = oneSystemLib.caisson.structural.mkTopConfiguration {
              moduleImports = _modules: [ ];
              configModule =
                { lib, ... }:
                {
                  caisson.nixos.configurations.original = lib.caisson.nixos.mkConfiguration {
                    configModule = probeModule;
                  };
                  caisson.nixos.exported = configurations: { renamed = configurations.original; };
                };
            };
          in
          builtins.attrNames top.nixosConfigurations;
        expected = [ "renamed" ];
      };

      # `publish` names the entries of an output attribute set from
      # their paths. Entries with the same path cannot be told apart,
      # and `publish` refuses them. The message names the output
      # attribute set and the path.
      "test: configurations with the same path are refused" = {
        expr =
          let
            entry = {
              attrset = "nixosConfigurations";
              value = "a NixOS configuration";
              manifest = { };
              path = [
                {
                  type = "nixos";
                  name = "probe";
                }
              ];
            };
            publishing =
              entries:
              (builtins.tryEval (builtins.deepSeq (myLib.caisson.integrations.publish entries) true)).success;
          in
          {
            once = publishing [ entry ];
            twice = publishing [
              entry
              entry
            ];
          };
        expected = {
          once = true;
          twice = false;
        };
      };

      # An output whose entries are keyed by system is published under
      # the system of each entry first, and named within it from the
      # path without its systems; with `single`, it holds the entry named
      # `default` for each system. An entry with no system is refused
      # there.
      "test: an output keyed by system publishes each entry under its system" = {
        expr =
          let
            entryFor =
              system: name: extra:
              {
                attrset = "packages";
                value = "${name} for ${system}";
                manifest = { };
                bySystem = true;
                inherit system;
                path = [
                  {
                    type = "system";
                    name = system;
                  }
                  {
                    type = "treefmt";
                    inherit name;
                  }
                ];
              }
              // extra;
            publish = myLib.caisson.integrations.publish;
            refused = entries: !(builtins.tryEval (builtins.deepSeq (publish entries) true)).success;
          in
          {
            named = publish [
              (entryFor "x86_64-linux" "a" { })
              (entryFor "x86_64-linux" "b" { })
              (entryFor "aarch64-linux" "a" { })
            ];
            single = publish [
              (entryFor "x86_64-linux" "formatter" {
                attrset = "formatter";
                single = true;
              })
              (entryFor "aarch64-linux" "formatter" {
                attrset = "formatter";
                single = true;
              })
            ];
            withoutSystem = refused [
              (entryFor "x86_64-linux" "a" { })
              (entryFor "x86_64-linux" "b" { system = null; })
            ];
          };
        expected = {
          named.packages = {
            x86_64-linux = {
              a = "a for x86_64-linux";
              b = "b for x86_64-linux";
            };
            aarch64-linux.a = "a for aarch64-linux";
          };
          single.formatter = {
            x86_64-linux = "formatter for x86_64-linux";
            aarch64-linux = "formatter for aarch64-linux";
          };
          withoutSystem = true;
        };
      };

      # A `lib` the caller passes in `specialArgs` takes precedence
      # over the `lib` the composition sets, the way every other special
      # argument does.
      # `mkIntegration` generates `mkTopConfiguration` from the `top`
      # function an integration declares. The generated function
      # takes the arguments of `mkConfiguration`, and its argument
      # pattern is the pattern of `mkConfiguration`.
      "test: the generated mkTopConfiguration takes the arguments of mkConfiguration" = {
        expr =
          let
            inherit (myLib.caisson-core.functions) functionArgs;
          in
          functionArgs myLib.caisson.nixos.mkTopConfiguration
          == functionArgs myLib.caisson.nixos.mkConfiguration
          && functionArgs myLib.caisson.nixos.mkConfiguration ? configModule;
        expected = true;
      };

      "test: the caller's specialArgs lib takes precedence" = {
        expr =
          (myLib.caisson.nixos.mkTopConfiguration {
            configModule = probeModule;
            specialArgs.lib = myLib // {
              caissonMarker = "from-specialArgs";
            };
          }).config.seenLib.marker;
        expected = "from-specialArgs";
      };
    };

  # The checks of configurations: what a configuration declares in
  # `caisson.checks`, what a caisson top gathers under `checks.<system>` of its
  # outputs, and the check record. The NixOS configurations evaluate
  # the stand-in nixos tree, and a check is a stand-in derivation: an
  # attribute set of type `derivation` with a store path.
  checks =
    let
      nixosStub = ./nixos-stub;
      checksLib = caisson.mkLib {
        dependencies = mockDependencies // {
          inherit nixosStub;
        };
        defaultEcosystemSrc = dependencies: {
          nixpkgs = dependencies.nixosStub;
          nixos = dependencies.nixosStub;
        };
        systems = [ "x86_64-linux" ];
        pkgSets = stubPkgSets { default = { }; };
        libOverlays = _lib: {
          nixos = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/nixos");
        };
      };
      check = name: {
        type = "derivation";
        inherit name;
        outPath = "/nix/store/00000000000000000000000000000000-${name}";
        drvPath = "/nix/store/00000000000000000000000000000000-${name}.drv";
      };
      nixosConfiguration =
        lib: module:
        lib.caisson.nixos.mkConfiguration {
          configModule = module;
        };
      topWith =
        module:
        checksLib.caisson.structural.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule = module;
        };
      # A structural caisson top with the NixOS configuration `nas-1`, which
      # declares the checks `smoke` and `off`, and turns `off` off, and
      # the structural configuration `lab` with the NixOS configuration
      # `arm` inside it, which declares the check `smoke`.
      gathering = topWith (
        { lib, ... }:
        {
          caisson.nixos.configurations.nas-1 = nixosConfiguration lib {
            caisson.checks.smoke = {
              derivation = check "nas-1-smoke";
              category = "eval";
            };
            caisson.checks.off = {
              derivation = check "nas-1-off";
              category = "eval";
              enable = false;
            };
          };
          caisson.structural.configurations.lab = lib.caisson.structural.mkConfiguration {
            moduleImports = _modules: [ ];
            configModule =
              { lib, ... }:
              {
                caisson.nixos.configurations.arm = nixosConfiguration lib {
                  caisson.checks.smoke = {
                    derivation = check "arm-smoke";
                    category = "eval";
                  };
                };
              };
          };
        }
      );
      names = top: builtins.mapAttrs (_: builtins.attrNames) top.checks;
    in
    {
      "test: a caisson top gathers the checks inside it under the joined names of the configurations" = {
        expr = {
          published = names gathering;
          inManifest = builtins.mapAttrs (_: builtins.attrNames) gathering.caisson.manifest.outputs.checks;
          record = builtins.mapAttrs (_: builtins.attrNames) gathering.caisson.manifest.checkRecord;
          smoke = gathering.checks.x86_64-linux.lab-arm-smoke.name;
        };
        expected = {
          published.x86_64-linux = [
            "lab-arm-smoke"
            "lab-arm-toplevel"
            "nas-1-smoke"
            "nas-1-toplevel"
            "registries"
          ];
          inManifest.x86_64-linux = [
            "lab-arm-smoke"
            "lab-arm-toplevel"
            "nas-1-smoke"
            "nas-1-toplevel"
            "registries"
          ];
          record.x86_64-linux = [
            "lab-arm-smoke"
            "lab-arm-toplevel"
            "nas-1-smoke"
            "nas-1-toplevel"
            "registries"
          ];
          smoke = "arm-smoke";
        };
      };

      "test: a check turned off stays in the manifest and is not gathered" = {
        expr =
          let
            recorded =
              gathering.caisson.manifest.children.system.x86_64-linux.children.nixos.nas-1.checks.x86_64-linux;
          in
          {
            names = builtins.attrNames recorded;
            enable = recorded.off.enable;
            gathered = gathering.checks.x86_64-linux ? nas-1-off;
          };
        expected = {
          names = [
            "off"
            "smoke"
            "toplevel"
          ];
          enable = false;
          gathered = false;
        };
      };

      "test: a check record entry says where the check is declared" = {
        expr = builtins.removeAttrs gathering.caisson.manifest.checkRecord.x86_64-linux.lab-arm-smoke [
          "code"
        ];
        expected = {
          name = "lab-arm-smoke";
          system = "x86_64-linux";
          from.namePath = [
            {
              type = "structural";
              name = "lab";
            }
            {
              type = "system";
              name = "x86_64-linux";
            }
            {
              type = "nixos";
              name = "arm";
            }
          ];
          category = "eval";
          description = null;
          volatile = false;
          requiredFeatures = [ ];
          top = null;
        };
      };

      "test: a category a configuration declares applies to every check the caisson top gathers" = {
        expr =
          let
            top = topWith (
              { lib, ... }:
              {
                caisson.checkCategories.hardware = {
                  description = "the machine boots on its hardware";
                  volatile = true;
                };
                caisson.nixos.configurations.nas-1 = nixosConfiguration lib {
                  # A check of a volatile category is a fixed-output
                  # derivation.
                  caisson.checks.boots = {
                    derivation = check "boots" // {
                      drvAttrs.outputHash = builtins.hashString "sha256" "pass\n";
                    };
                    category = "hardware";
                  };
                };
              }
            );
          in
          {
            inherit (top.caisson.manifest.checkRecord.x86_64-linux.nas-1-boots) category volatile;
            declared = builtins.attrNames top.caisson.manifest.checkCategories;
          };
        expected = {
          category = "hardware";
          volatile = true;
          declared = [
            "build"
            "eval"
            "format"
            "hardware"
            "unit"
            "vm"
          ];
        };
      };

      "test: a check whose category nothing declares is refused with the check and its file" = {
        expr =
          let
            top = topWith (
              { lib, ... }:
              {
                caisson.nixos.configurations.nas-1 = nixosConfiguration lib {
                  caisson.checks.smoke = {
                    derivation = check "smoke";
                    category = "undeclared";
                  };
                };
              }
            );
          in
          top.checks.x86_64-linux.nas-1-smoke.drvPath;
        expectedError = {
          type = "ThrownError";
          msg = "the check `smoke` of the configuration at children\\.system\\.x86_64-linux\\.children\\.nixos\\.nas-1,\\s+declared at [^ ]*lib-overlays\\.nix:[0-9]+, names the category `undeclared`, which no";
        };
      };

      "test: checks gathered under the same name are refused" = {
        expr =
          let
            top = topWith (
              { lib, ... }:
              {
                caisson.nixos.configurations.nas-1 = nixosConfiguration lib {
                  caisson.checks.smoke = {
                    derivation = check "smoke";
                    category = "eval";
                  };
                };
                caisson.nixos.configurations.nas = nixosConfiguration lib {
                  caisson.checks."1-smoke" = {
                    derivation = check "other-smoke";
                    category = "eval";
                  };
                };
              }
            );
          in
          builtins.attrNames top.checks.x86_64-linux;
        expectedError = {
          type = "ThrownError";
          msg = "checks\\.x86_64-linux: these checks would be gathered under the same\\s+name, `nas-1-smoke`";
        };
      };

      "test: a check that names no category is refused" = {
        expr =
          let
            top = topWith (
              { lib, ... }:
              {
                caisson.nixos.configurations.nas-1 = nixosConfiguration lib {
                  caisson.checks.smoke.derivation = check "smoke";
                };
              }
            );
          in
          builtins.attrNames top.checks.x86_64-linux;
        expectedError = {
          type = "ThrownError";
          msg = "`caisson\\.checks\\.smoke` of the nixos configuration `nas-1`, defined at [^ ]*lib-overlays\\.nix:[0-9]+, declares a check and names no `category`";
        };
      };

      "test: an annotation with no check to annotate is refused" = {
        expr =
          let
            top = topWith (
              { lib, ... }:
              {
                caisson.nixos.configurations.nas-1 = nixosConfiguration lib {
                  caisson.checks.missing.enable = false;
                };
              }
            );
          in
          builtins.attrNames top.checks.x86_64-linux;
        expectedError = {
          type = "ThrownError";
          msg = "annotates the check `missing`, and the configuration\\s+has no check of that name";
        };
      };

      "test: the caisson top records its stages" = {
        expr =
          let
            top = topWith {
              caisson.checkStages.quick = {
                description = "the checks that evaluate";
                select = entry: entry.category == "eval";
              };
            };
          in
          {
            inherit (top.caisson.manifest.checkStages.quick) description;
            selects = top.caisson.manifest.checkStages.quick.select { category = "eval"; };
          };
        expected = {
          description = "the checks that evaluate";
          selects = true;
        };
      };

      "test: a stage declared inside the caisson top is refused" = {
        expr =
          let
            top = topWith (
              { lib, ... }:
              {
                caisson.nixos.configurations.nas-1 = nixosConfiguration lib {
                  caisson.checkStages.inner = {
                    description = "a stage inside the caisson top";
                    select = _: true;
                  };
                };
              }
            );
          in
          builtins.attrNames top.checks;
        expectedError = {
          type = "ThrownError";
          msg = "children\\.system\\.x86_64-linux\\.children\\.nixos\\.nas-1 declares stages of checks";
        };
      };

      "test: a flake annotates the entries of checks under perSystem" = {
        expr =
          let
            flake = checksLib.caisson.flake-parts.mkTopConfiguration {
              moduleImports = _modules: [ ];
              configModule =
                { lib, ... }:
                {
                  perSystem = {
                    checks.treefmt = check "treefmt";
                    checks.bare = check "bare";
                    caisson.checks.treefmt.category = "format";
                    caisson.checks.declared = {
                      derivation = check "declared";
                      category = "unit";
                      description = "the unit tests pass";
                    };
                  };
                  caisson.nixos.configurations.nas-1 = nixosConfiguration lib {
                    caisson.checks.smoke = {
                      derivation = check "smoke";
                      category = "eval";
                    };
                  };
                };
            };
            record = flake.caisson.manifest.checkRecord.x86_64-linux;
          in
          {
            published = names flake;
            categories = builtins.mapAttrs (_: entry: entry.category) record;
            treefmtPositions = builtins.length record.treefmt.code;
            description = record.declared.description;
          };
        expected = {
          published.x86_64-linux = [
            "bare"
            "declared"
            "nas-1-smoke"
            "nas-1-toplevel"
            "registries"
            "treefmt"
          ];
          categories = {
            bare = "build";
            declared = "unit";
            nas-1-smoke = "eval";
            nas-1-toplevel = "build";
            registries = "eval";
            treefmt = "format";
          };
          treefmtPositions = 2;
          description = "the unit tests pass";
        };
      };

      "test: a caisson top whose configurations declare no checks gathers the default checks alone" = {
        expr =
          let
            top = topWith (
              { lib, ... }:
              {
                caisson.nixos.configurations.nas-1 = nixosConfiguration lib { };
              }
            );
          in
          {
            checks = names top;
            record = builtins.mapAttrs (_: builtins.attrNames) top.caisson.manifest.checkRecord;
          };
        expected = {
          checks.x86_64-linux = [
            "nas-1-toplevel"
            "registries"
          ];
          record.x86_64-linux = [
            "nas-1-toplevel"
            "registries"
          ];
        };
      };

      "test: a check with `top` publishes the checks of the test caisson top under its name" = {
        expr =
          let
            flake = checksLib.caisson.flake-parts.mkTopConfiguration {
              moduleImports = _modules: [ ];
              configModule = {
                perSystem = {
                  # A test caisson top that publishes a check record.
                  caisson.checks.basic.top = {
                    checks.x86_64-linux = {
                      smoke = check "smoke";
                      plain = check "plain";
                    };
                    caisson.manifest.checkRecord.x86_64-linux.smoke = {
                      category = "eval";
                      description = "the smoke test passes";
                    };
                  };
                  # A flake that is no caisson top, with a category for
                  # its checks.
                  caisson.checks.other = {
                    top.checks.x86_64-linux.a = check "a";
                    category = "unit";
                  };
                };
              };
            };
            # The record entries of the checks of the test caisson tops,
            # beside which the caisson top records its default check
            # `registries`.
            record = builtins.removeAttrs flake.caisson.manifest.checkRecord.x86_64-linux [ "registries" ];
          in
          {
            published = builtins.attrNames record;
            smoke = flake.checks.x86_64-linux.basic-smoke.name;
            categories = builtins.mapAttrs (_: entry: entry.category) record;
            descriptions = builtins.mapAttrs (_: entry: entry.description) record;
            tops = builtins.mapAttrs (_: entry: entry.top) record;
          };
        expected = {
          published = [
            "basic-plain"
            "basic-smoke"
            "other-a"
          ];
          smoke = "smoke";
          categories = {
            basic-plain = "build";
            basic-smoke = "eval";
            other-a = "unit";
          };
          descriptions = {
            basic-plain = null;
            basic-smoke = "the smoke test passes";
            other-a = null;
          };
          tops = {
            basic-plain = {
              name = "basic";
              check = "plain";
              record = null;
            };
            basic-smoke = {
              name = "basic";
              check = "smoke";
              record = {
                category = "eval";
                description = "the smoke test passes";
              };
            };
            other-a = {
              name = "other";
              check = "a";
              record = null;
            };
          };
        };
      };

      "test: a check with both `top` and `derivation` is refused" = {
        expr =
          let
            flake = checksLib.caisson.flake-parts.mkTopConfiguration {
              moduleImports = _modules: [ ];
              configModule = {
                perSystem.caisson.checks.basic = {
                  top.checks.x86_64-linux.smoke = check "smoke";
                  derivation = check "basic";
                  category = "eval";
                };
              };
            };
          in
          builtins.attrNames flake.checks.x86_64-linux;
        expectedError = {
          type = "ThrownError";
          msg = "`caisson\\.checks\\.basic` of the flake-parts configuration at the caisson top, defined at [^ ]*lib-overlays\\.nix:[0-9]+,\\s+sets both a `derivation` and a `top`";
        };
      };
    };

  # The dependencies a flake-parts configuration declared inside a
  # caisson top adds to those of the caisson top: the flake's `inputs`
  # inside it hold both, a name the caisson top pins keeps the
  # dependency of the caisson top, and the manifest records the added
  # dependencies with their pin files relative to the root.
  nestedDependencies =
    let
      pin = dir: {
        system = "flake";
        files = {
          refs = "flake.nix";
          revisions = "flake.lock";
        };
        inherit dir;
        url = null;
        follows = null;
      };
      added = {
        extra = {
          outPath = "/extra";
          pin = pin "/src/tests/dependencies";
        };
        nixpkgs-lib = {
          outPath = "/shadowed-nixpkgs-lib";
          pin = pin "/src/tests/dependencies";
        };
      };
      dependenciesLib = caisson.mkLib {
        dependencies = mockDependencies;
        root.outPath = "/src";
        systems = [ "x86_64-linux" ];
      };
      topWith =
        child:
        dependenciesLib.caisson.flake-parts.mkTopConfiguration {
          moduleImports = _modules: [ ];
          configModule =
            { lib, ... }:
            {
              caisson.flake-parts.configurations.checks = child lib;
            };
        };
      flake = topWith (
        lib:
        lib.caisson.flake-parts.mkConfiguration {
          dependencies = added;
          moduleImports = _modules: [ ];
          configModule =
            { inputs, ... }:
            {
              flake.seen = {
                extra = inputs.extra.outPath;
                nixpkgs-lib = inputs.nixpkgs-lib.outPath;
              };
            };
        }
      );
      child = flake.caisson.manifest.children.flake-parts.checks;
    in
    {
      "test: a nested flake-parts configuration sees the added dependencies beside those of the caisson top" =
        {
          expr = child.outputs.flake.seen;
          expected = {
            extra = "/extra";
            nixpkgs-lib = mockDependencies.nixpkgs-lib.outPath;
          };
        };

      "test: an added dependency the caisson top already pins is recorded as shadowed" = {
        expr = {
          dependencies = builtins.attrNames child.dependencies;
          shadowed = builtins.attrNames child.shadowedDependencies;
          shadowedTree = child.shadowedDependencies.nixpkgs-lib.outPath;
          kept = child.dependencies.nixpkgs-lib.outPath;
        };
        expected = {
          dependencies = builtins.attrNames (mockDependencies // { extra = null; });
          shadowed = [ "nixpkgs-lib" ];
          shadowedTree = "/shadowed-nixpkgs-lib";
          kept = mockDependencies.nixpkgs-lib.outPath;
        };
      };

      "test: the manifest records the pin files of an added dependency relative to the root" = {
        expr = {
          added = child.dependencies.extra.pin;
          shadowed = child.shadowedDependencies.nixpkgs-lib.pin.files;
        };
        expected = {
          added = {
            system = "flake";
            files = {
              refs = "tests/dependencies/flake.nix";
              revisions = "tests/dependencies/flake.lock";
            };
            url = null;
            follows = null;
          };
          shadowed = {
            refs = "tests/dependencies/flake.nix";
            revisions = "tests/dependencies/flake.lock";
          };
        };
      };

      "test: a configuration declared inside the nested configuration sees the added dependencies" = {
        expr =
          let
            nested = topWith (
              lib:
              lib.caisson.flake-parts.mkConfiguration {
                dependencies = added;
                moduleImports = _modules: [ ];
                configModule =
                  { lib, ... }:
                  {
                    caisson.flake-parts.configurations.inner = lib.caisson.flake-parts.mkConfiguration {
                      moduleImports = _modules: [ ];
                      configModule =
                        { inputs, ... }:
                        {
                          flake.seen = inputs.extra.outPath;
                        };
                    };
                  };
              }
            );
          in
          nested.caisson.manifest.children.flake-parts.checks.children.flake-parts.inner.outputs.flake.seen;
        expected = "/extra";
      };

      "test: reading the exports of the caisson top reads no dependency of a configuration its selector passes up to nothing" =
        {
          expr =
            let
              top = dependenciesLib.caisson.flake-parts.mkTopConfiguration {
                moduleImports = _modules: [ ];
                configModule =
                  { lib, ... }:
                  {
                    caisson.flake-parts.configurations.checks = lib.caisson.flake-parts.mkConfiguration {
                      dependencies = throw "the dependencies of the checks configuration were read";
                      moduleImports = _modules: [ ];
                    };
                    caisson.flake-parts.exported = _: { };
                  };
              };
              exports = top.caisson.manifest.outputs.exports;
            in
            {
              exports = builtins.attrNames exports.libOverlays ++ builtins.attrNames exports.modules;
              configurations = exports.configurations;
              lib = top.lib.caisson-core.evalManifest._type;
              # The `checks` output reads the configuration, so it reads
              # the dependencies, which throw.
              checks = (builtins.tryEval (builtins.attrNames top.checks.x86_64-linux)).success;
            };
          expected = {
            # The lib overlays the test library registers.
            exports = [
              "flake-parts"
              "structural"
            ];
            configurations = [ ];
            lib = "caisson-manifest";
            checks = false;
          };
        };

      "test: dependencies given to the configuration at the caisson top are refused" = {
        expr =
          builtins.attrNames
            (dependenciesLib.caisson.flake-parts.mkTopConfiguration {
              dependencies = added;
              moduleImports = _modules: [ ];
            }).caisson.manifest.dependencies;
        expectedError = {
          type = "ThrownError";
          msg = "is given `dependencies`\\. A configuration is given\\s+`dependencies` when it is declared inside another configuration";
        };
      };
    };

  # The home-manager integration as a library integration: `lib.hm` is
  # an entry of the integration, composed over the library the
  # composition builds, and a home-manager evaluation runs on that
  # library. The ecosystem source is a stand-in source tree with the
  # files the integration reads, `modules/lib` (the function composed
  # as the `hm` entry) and `modules/modules.nix` (the module list),
  # each with the signature of the file it stands in for.
  homeManagerLib =
    let
      hmStub = ./home-manager-stub;
      # The same stub at a second path, the store copy of the parent
      # flake: a source tree equal in content to the declared source
      # tree at a different path, so a configuration can name another
      # home-manager and nothing but the refusal stands in its way.
      hmStubCopy = inputs.parent.outPath + "/tests/unit/home-manager-stub";
      # A home-manager configuration takes its system and its package
      # set from the composition: one system, and a stand-in set named
      # `default`.
      homeManagerComposition = {
        systems = [ "x86_64-linux" ];
        pkgSets = stubPkgSets { default = { }; };
      };
      mkCompositionWith =
        declaration: extraOverlays:
        caisson.mkLib (
          homeManagerComposition
          // {
            dependencies = mockDependencies // {
              inherit hmStub hmStubCopy;
            };
            libOverlays =
              _lib:
              {
                home-manager = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/home-manager");
                # The marker this composition adds and nothing else
                # does: reading it inside the evaluation shows which
                # library got there.
                marker = mkLibOverlay (
                  { ... }:
                  {
                    overlay = _final: _prev: {
                      caissonMarker = "from-the-composition";
                    };
                  }
                );
              }
              // extraOverlays;
          }
          // declaration
        );
      mkComposition = mkCompositionWith {
        defaultEcosystemSrc = dependencies: { home-manager = dependencies.hmStub; };
      };
      myLib = mkComposition { };
      # A composition that declares no home-manager: no
      # `defaultEcosystemSrc.home-manager`, and no input of that name.
      # The home-manager source comes from the `ecosystemSrc` of each
      # configuration.
      undeclaredLib = mkCompositionWith { } { };
      # A nixpkgs maintainer list for a composition to merge into. The
      # nixpkgs.lib mirror these tests compose on has none, so a
      # composition that reads the merged name supplies a list: the
      # home-manager entry imports it, which puts it in `prev` where
      # the merge reads it.
      nixpkgsMaintainers = {
        key = "a-nixpkgs-maintainer-list";
        overlay = _final: _prev: {
          maintainers.a-nixpkgs-maintainer = { };
        };
      };
      mkMaintainersComposition =
        declaration:
        caisson.mkLib (
          homeManagerComposition
          // {
            dependencies = mockDependencies // {
              inherit hmStub;
            };
            libOverlays = _lib: {
              home-manager = {
                imports = [
                  nixpkgsMaintainers
                  (mkLibOverlay (inputs.parent.outPath + "/lib-overlays/home-manager"))
                ];
                overlay = _final: _prev: { };
              };
            };
          }
          // declaration
        );
      # A configuration module that records what the library the
      # module system handed it contains.
      probeModule =
        { lib, ... }:
        {
          seenLib = {
            # An attribute this composition contributed and nixpkgs
            # does not have: present only if the library the modules
            # run on is the composed library.
            marker = lib.caissonMarker or null;
            # The name home-manager's modules read.
            hm = lib.hm.reachesLib or null;
            # A function of `hm` calling back through `lib.hm`: the
            # self-reference resolves through the composed fixpoint.
            viaFixpoint = (lib.hm.dag.entryAnywhere "x").viaFixpoint or null;
            # The home-manager maintainers under the name they are
            # read by. The merged `lib.maintainers` forces nixpkgs'
            # list, which lives beside the `lib` directory and so is
            # absent from the nixpkgs.lib mirror these tests compose
            # on; the home-manager half is read through `hm`.
            maintainer = lib.hm.maintainers ? home-manager-stub-maintainer;
            # A nixpkgs function, so the composed library is still
            # nixpkgs' library and not a bare `hm`.
            nixpkgs = lib.isFunction lib.id;
          };
        };
      # A composition for home-manager configurations in a flake: the
      # systems given, the package configs `default` and `other`, whose
      # set for a system says which it is, NixOS configurations over
      # the stand-in nixpkgs source tree, and a home-manager
      # configuration registered under the name `chris`.
      flakeLibWith =
        systems:
        caisson.mkLib {
          dependencies = mockDependencies // {
            nixosStub = ./nixos-stub;
            inherit hmStub;
          };
          name = "home-manager-configurations";
          defaultEcosystemSrc = dependencies: {
            nixpkgs = dependencies.nixosStub;
            nixos = dependencies.nixosStub;
            home-manager = dependencies.hmStub;
          };
          inherit systems;
          pkgSets =
            _lib:
            lib.genAttrs
              [
                "default"
                "other"
              ]
              (
                config:
                { name, parent }:
                {
                  _type = "caisson-manifest";
                  type = "nixpkgs";
                  inherit name parent;
                  children.nixpkgs = lib.genAttrs systems (system: {
                    _type = "caisson-manifest";
                    type = "nixpkgs";
                    name = system;
                    value.marker = "${config} for ${system}";
                  });
                }
              );
          libOverlays = _lib: {
            home-manager = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/home-manager");
            nixos = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/nixos");
          };
          # caisson's `default` NixOS module, which a flake that takes
          # caisson as a project has in its registry. A NixOS
          # configuration imports it unless the NixOS configuration
          # passes `moduleImports`.
          modules = _lib: {
            nixos = {
              inherit (lib.caisson.modules.nixos) default;
            };
          };
          # A package overlay of the flake itself, which adds nothing.
          # A configuration exports the package overlays its library
          # registers, so every configuration built on this library
          # has one to export.
          pkgOverlays = _lib: {
            tools.overlay = _final: _prev: { };
          };
          configs = callbackLib: {
            homeManager.chris = callbackLib.caisson.home-manager.mkModule (
              { ... }:
              { ... }:
              {
                seenLib.registered = true;
              }
            );
          };
        };
      # A flake with a home-manager configuration alone and a NixOS
      # configuration `laptop` on the set `other` with two home-manager
      # configurations, the second naming another user and selecting
      # `default`. `serving` adds a NixOS configuration `server` that
      # holds a configuration for another system.
      homeManagerConfiguration =
        lib: args: lib.caisson.home-manager.mkConfiguration ({ check = false; } // args);
      flakeWith =
        { serving }:
        { lib, ... }:
        {
          caisson.home-manager.configurations.chris = homeManagerConfiguration lib { };
          caisson.nixos.configurations = {
            laptop = lib.caisson.nixos.mkConfiguration {
              defaultPkgs = pkgSets: pkgSets.other;
              configModule =
                { lib, ... }:
                {
                  caisson.home-manager.configurations.chris = homeManagerConfiguration lib { };
                  caisson.home-manager.configurations.dana = homeManagerConfiguration lib {
                    defaultPkgs = pkgSets: pkgSets.default;
                    configModule = {
                      home.username = "someone-else";
                    };
                  };
                };
            };
          }
          // lib.optionalAttrs serving {
            server = lib.caisson.nixos.mkConfiguration {
              configModule =
                { lib, ... }:
                {
                  caisson.forChildren.systems = [ "aarch64-linux" ];
                  caisson.nixos.configurations.image = lib.caisson.nixos.mkConfiguration {
                    configModule = { };
                  };
                };
            };
          };
        };
      # A home-manager configuration finalized as a caisson top, read as the
      # home-manager CLI reads it: the evaluated home-manager
      # configuration.
      configuration = myLib.caisson.home-manager.mkTopConfiguration {
        configModule = probeModule;
        check = false;
      };
      # The same for a configuration an entry point with no
      # `mkTopConfiguration` returned.
      topOf =
        composition: declared:
        composition.caisson.integrations.topValue (composition.caisson-core.finalizeTop declared);
    in
    {
      # The proof that the composed library is passed to the modules:
      # while the configuration is evaluated, a module sees the
      # composition's marker and `lib.hm` on the same library. Composing `hm` with
      # `lib.extend` inside the evaluator cannot produce this: nixpkgs'
      # `lib/default.nix` builds its fixpoint with a bootstrap
      # `makeExtensible` that keeps no `__unfix__`, so `extend`
      # re-derives nixpkgs' fixpoint and `marker` comes back null while
      # `hm` is set.
      "test: the modules see the composition and lib.hm on one library" = {
        expr = configuration.config.seenLib;
        expected = {
          marker = "from-the-composition";
          hm = "from-the-composition";
          viaFixpoint = "from-the-composition";
          maintainer = true;
          nixpkgs = true;
        };
      };

      # `hm` is an entry of the composed library, so it is there
      # before any evaluation and every reader of the library sees it.
      "test: lib.hm is an attribute of the composed library" = {
        expr = myLib.hm.reachesLib;
        expected = "from-the-composition";
      };

      # The entry merges the home-manager maintainers into the
      # nixpkgs maintainer list, the name the `meta.maintainers` type
      # check of nixpkgs reads.
      "test: lib.maintainers holds both lists" = {
        expr =
          builtins.attrNames
            (mkMaintainersComposition {
              defaultEcosystemSrc = dependencies: { home-manager = dependencies.hmStub; };
            }).maintainers;
        expected = [
          "a-nixpkgs-maintainer"
          "home-manager-stub-maintainer"
        ];
      };

      # With no home-manager declared there are no maintainers to
      # merge, and the list is what the composition had.
      "test: a composition declaring no home-manager leaves lib.maintainers as it found it" = {
        expr = builtins.attrNames (mkMaintainersComposition { }).maintainers;
        expected = [ "a-nixpkgs-maintainer" ];
      };

      # The library a configuration that names its home-manager runs on
      # merges the maintainers of the home-manager source it names, the
      # way the entry does for a declared source.
      "test: a configuration naming its home-manager merges its maintainers" = {
        expr =
          ((mkMaintainersComposition { }).caisson.home-manager.mkTopConfiguration {
            ecosystemSrc = dependencies: dependencies.hmStub;
            configModule =
              { lib, ... }:
              {
                seenLib.maintainers = builtins.attrNames lib.maintainers;
              };
            check = false;
          }).config.seenLib.maintainers;
        expected = [
          "a-nixpkgs-maintainer"
          "home-manager-stub-maintainer"
        ];
      };

      # `lib.hm` of a composition that declares no home-manager is a
      # read of nothing, and says so.
      "test: lib.hm of a composition declaring no home-manager names the declaration" = {
        expr = builtins.deepSeq undeclaredLib.hm true;
        expectedError = {
          type = "ThrownError";
          msg = "lib\\.hm: this composition declares no home-manager\\.";
        };
      };

      # An entry is replaceable by key. The integration's entry is
      # keyed `home-manager`, so a same-key entry takes its place.
      "test: the hm entry is replaceable by its key" = {
        expr =
          (mkComposition {
            home-manager = {
              key = "home-manager";
              overlay = _final: _prev: {
                hm = {
                  reachesLib = "from-a-replacement-entry";
                };
              };
            };
          }).hm.reachesLib;
        expected = "from-a-replacement-entry";
      };

      # The home-manager integration composes home-manager's module
      # list from the declared source and hands it `modulesPath`, the
      # special argument home-manager's news entries interpolate. It
      # asks for the list without home-manager's nixpkgs module, so the
      # home-manager configuration runs on the package set it is given.
      "test: the integration reads the module list of the declared source" = {
        expr = {
          inherit (configuration.config.stub) minimal useNixpkgsModule;
          # The tail of the path, the head being the store copy of the
          # source tree the test flake declared.
          modulesPath = lib.hasSuffix "/home-manager-stub/modules" configuration.config.stub.modulesPath;
        };
        expected = {
          modulesPath = true;
          minimal = false;
          useNixpkgsModule = false;
        };
      };

      # What the evaluation result holds beside the configuration: the
      # names `modules/default.nix` of the home-manager source adds.
      "test: the evaluation result holds the activation package and the news" = {
        expr = {
          inherit (configuration)
            activationPackage
            activation-script
            newsDisplay
            newsEntries
            ;
          extendModules = builtins.isFunction configuration.extendModules;
        };
        expected = {
          activationPackage = "activation-package";
          activation-script = "activation-package";
          newsDisplay = "silent";
          newsEntries = [ ];
          extendModules = true;
        };
      };

      # Evaluating the configuration collects its failed assertions
      # and throws with their messages.
      "test: a failed assertion stops the evaluation" = {
        expr =
          (builtins.tryEval
            (myLib.caisson.home-manager.mkTopConfiguration {
              configModule = {
                assertions = [
                  {
                    assertion = false;
                    message = "the stub assertion";
                  }
                ];
              };
              check = false;
            }).activationPackage
          ).success;
        expected = false;
      };

      "test: the WithEcosystemArgs variant replaces the library like any evaluator argument" = {
        expr =
          (topOf myLib (
            myLib.caisson.home-manager.mkConfigurationWithEcosystemArgs {
              configModule = probeModule;
              check = false;
              ecosystemArgs.lib = myLib // {
                caissonMarker = "from-ecosystemArgs";
              };
            }
          )).config.seenLib.marker;
        expected = "from-ecosystemArgs";
      };

      # An `ecosystemSrc` naming the declared source names the source
      # the entry composed `hm` from, and the configuration runs on the
      # composed library.
      "test: a configuration naming the declared source runs on the composed library" = {
        expr =
          (myLib.caisson.home-manager.mkTopConfiguration {
            ecosystemSrc = dependencies: dependencies.hmStub;
            configModule = probeModule;
            check = false;
          }).config.seenLib;
        expected = {
          marker = "from-the-composition";
          hm = "from-the-composition";
          viaFixpoint = "from-the-composition";
          maintainer = true;
          nixpkgs = true;
        };
      };

      # A home-manager configuration is evaluated on a single library,
      # so its modules and its `lib.hm` come from the same source. The
      # declared source composed `hm`, and a configuration naming
      # another source is refused, with the declaration that would
      # compose an `hm` for it.
      "test: a configuration naming a second source beside the declared source is refused" = {
        expr =
          builtins.deepSeq
            (myLib.caisson.home-manager.mkTopConfiguration {
              ecosystemSrc = dependencies: dependencies.hmStubCopy;
              configModule = probeModule;
              check = false;
            }).config.seenLib
            true;
        expectedError = {
          type = "ThrownError";
          msg = "as its home-manager, and the composed library holds `lib\\.hm`";
        };
      };

      # With no home-manager declared, the source a configuration names
      # supplies its modules and its `lib.hm`: the modules see the
      # composition's marker and `lib.hm`, `hm` calls back through
      # `lib.hm` on the library the configuration runs on, and the
      # home-manager maintainers are there under `hm`.
      "test: a configuration names its home-manager when the composition declares none" = {
        expr =
          (undeclaredLib.caisson.home-manager.mkTopConfiguration {
            ecosystemSrc = dependencies: dependencies.hmStub;
            configModule = probeModule;
            check = false;
          }).config.seenLib;
        expected = {
          marker = "from-the-composition";
          hm = "from-the-composition";
          viaFixpoint = "from-the-composition";
          maintainer = true;
          nixpkgs = true;
        };
      };

      # The modules of such a configuration read `lib.hm.dag` the way
      # the modules of home-manager do, and the `lib` option the module
      # list sets to `lib.hm` is that same library.
      "test: the modules of a configuration naming its home-manager read lib.hm" = {
        expr =
          let
            evaluated = undeclaredLib.caisson.home-manager.mkTopConfiguration {
              ecosystemSrc = dependencies: dependencies.hmStub;
              configModule =
                { config, lib, ... }:
                {
                  seenLib = {
                    dag = (lib.hm.dag.entryAnywhere "x").data;
                    libOption = config.lib.reachesLib;
                  };
                };
              check = false;
            };
          in
          evaluated.config.seenLib;
        expected = {
          dag = "x";
          libOption = "from-the-composition";
        };
      };

      # The module system hands out the library the configuration runs
      # on wherever it creates a module: a submodule and an
      # `evalModules` call inside a module both see the composition and
      # `lib.hm`, under a declared home-manager and under a
      # home-manager the configuration names.
      "test: submodules and nested evaluations run on the same library" = {
        expr =
          let
            innerModule =
              { lib, ... }:
              {
                options.seen = lib.mkOption {
                  type = lib.types.attrs;
                  default = {
                    marker = lib.caissonMarker or null;
                    hm = lib.hm.reachesLib or null;
                  };
                };
              };
            probe =
              { config, lib, ... }:
              {
                options.sub = lib.mkOption {
                  type = lib.types.submodule innerModule;
                  default = { };
                };
                config.seenLib = {
                  submodule = config.sub.seen;
                  nested = (lib.evalModules { modules = [ innerModule ]; }).config.seen;
                };
              };
            seenUnder =
              composition: args:
              (composition.caisson.home-manager.mkTopConfiguration (
                {
                  configModule = probe;
                  check = false;
                }
                // args
              )).config.seenLib;
          in
          {
            declared = seenUnder myLib { };
            named = seenUnder undeclaredLib { ecosystemSrc = dependencies: dependencies.hmStub; };
          };
        expected = {
          declared = {
            submodule = {
              marker = "from-the-composition";
              hm = "from-the-composition";
            };
            nested = {
              marker = "from-the-composition";
              hm = "from-the-composition";
            };
          };
          named = {
            submodule = {
              marker = "from-the-composition";
              hm = "from-the-composition";
            };
            nested = {
              marker = "from-the-composition";
              hm = "from-the-composition";
            };
          };
        };
      };

      # With no home-manager declared and none named, there is no
      # home-manager source to evaluate: the miss is reported with the
      # places a source comes from.
      "test: a configuration naming no home-manager under no declaration is refused" = {
        expr =
          builtins.deepSeq
            (undeclaredLib.caisson.home-manager.mkTopConfiguration {
              configModule = probeModule;
              check = false;
            }).config.seenLib
            true;
        expectedError = {
          type = "ThrownError";
          msg = "caisson\\.home-manager: no home-manager ecosystem source\\.";
        };
      };

      # A home-manager configuration is a configuration. Declared
      # inside another configuration it takes the module registered
      # under its name, its user is the name it is declared under
      # unless a module of the home-manager configuration names
      # another, and it runs on the package set selected where it is
      # declared: inside a NixOS configuration the set of that
      # configuration, unless the home-manager configuration selects.
      # A caisson top publishes it under `homeConfigurations`. Inside a NixOS
      # configuration its name is `<user>@<name>`, where `<name>` is the
      # name of the NixOS configuration. Elsewhere its name is the name
      # it is declared under.
      "test: a home-manager configuration declared inside a configuration is named, published and given its package set" =
        {
          expr =
            let
              lib = flakeLibWith [ "x86_64-linux" ];
              top = lib.caisson.structural.mkTopConfiguration {
                moduleImports = _modules: [ ];
                configModule = flakeWith { serving = false; };
              };
              homeManagerConfigurations = top.homeConfigurations;
              seen = homeManagerConfiguration: {
                user = homeManagerConfiguration.config.home.username;
                set = homeManagerConfiguration.pkgs.marker;
              };
            in
            {
              names = builtins.attrNames homeManagerConfigurations;
              alone = seen homeManagerConfigurations.chris // {
                registered = homeManagerConfigurations.chris.config.seenLib.registered;
              };
              insideANixosConfiguration = seen homeManagerConfigurations."chris@laptop";
              selecting = seen homeManagerConfigurations."dana@laptop";
              aTopHasNoDeclaredName =
                (lib.caisson.home-manager.mkTopConfiguration {
                  configModule = { };
                  check = false;
                }).config.home.username;
            };
          expected = {
            names = [
              "chris"
              "chris@laptop"
              "dana@laptop"
            ];
            alone = {
              user = "chris";
              set = "default for x86_64-linux";
              registered = true;
            };
            insideANixosConfiguration = {
              user = "chris";
              set = "other for x86_64-linux";
            };
            selecting = {
              user = "someone-else";
              set = "default for x86_64-linux";
            };
            aTopHasNoDeclaredName = "";
          };
        };

      # A home-manager configuration declared inside a NixOS
      # configuration is given the evaluation result of that NixOS
      # configuration. The home-manager integration hands it the
      # `config` of the NixOS configuration as `osConfig`. The `default`
      # NixOS module of caisson adds the module `nixos-parent` to the
      # modules the home-manager configuration imports by default, and
      # that module sets the home directory and the user ID from the
      # account the NixOS configuration declares, the Nix of the NixOS
      # configuration, and the option home-manager reads to tell that a
      # NixOS configuration activates the home-manager configuration.
      #
      # The five home-manager configurations below are these. A
      # home-manager configuration whose account the NixOS configuration
      # declares. A home-manager configuration whose account the NixOS
      # configuration does not declare, as with an account that
      # systemd-homed manages. A home-manager configuration that passes
      # `moduleImports` and so selects its modules itself. A
      # home-manager configuration inside a NixOS configuration that
      # passes `moduleImports`, and so does not import the `default`
      # NixOS module. A home-manager configuration declared outside any
      # NixOS configuration.
      "test: a home-manager configuration declared inside a NixOS configuration is given its evaluation result" =
        {
          expr =
            let
              lib = flakeLibWith [ "x86_64-linux" ];
              # What a home-manager configuration sees of its NixOS
              # configuration through `osConfig`.
              probe =
                { osConfig, ... }:
                {
                  seenLib.parentNix = if osConfig == null then null else osConfig.nix.package;
                  programs.home-manager.enable = true;
                };
              # The class of the NixOS configuration, which only a
              # home-manager configuration inside a NixOS configuration is
              # handed.
              classProbe =
                { osClass, ... }:
                {
                  seenLib.parentClass = osClass;
                };
              top = lib.caisson.structural.mkTopConfiguration {
                moduleImports = _modules: [ ];
                configModule =
                  { lib, ... }:
                  {
                    caisson.home-manager.configurations.alone = homeManagerConfiguration lib { configModule = probe; };
                    caisson.nixos.configurations.laptop = lib.caisson.nixos.mkConfiguration {
                      configModule =
                        { lib, ... }:
                        {
                          users.users.declared = {
                            home = "/home/declared";
                            uid = 1001;
                          };
                          caisson.home-manager.configurations = {
                            declared = homeManagerConfiguration lib {
                              configModule.imports = [
                                probe
                                classProbe
                              ];
                            };
                            undeclared = homeManagerConfiguration lib { configModule = probe; };
                            selecting = homeManagerConfiguration lib {
                              configModule = probe;
                              moduleImports = _modules: [ ];
                            };
                          };
                        };
                    };
                    # A NixOS configuration that selects its modules
                    # itself. It does not import caisson's `default`
                    # NixOS module, so it adds nothing to the default
                    # modules of the home-manager configuration declared
                    # inside it.
                    caisson.nixos.configurations.bare = lib.caisson.nixos.mkConfiguration {
                      moduleImports = _modules: [ ];
                      configModule =
                        { lib, ... }:
                        {
                          users.users.declared = {
                            home = "/home/declared";
                            uid = 1001;
                          };
                          caisson.home-manager.configurations.declared = homeManagerConfiguration lib {
                            configModule = probe;
                          };
                        };
                    };
                  };
              };
              seen =
                homeManagerConfiguration:
                let
                  inherit (homeManagerConfiguration) config;
                in
                {
                  inherit (config.seenLib) parentNix;
                  inherit (config.home) homeDirectory uid packages;
                  nix = config.nix.package;
                  activatedByTheParent = config.submoduleSupport.enable;
                };
              homeManagerConfigurations = top.homeConfigurations;
            in
            {
              declared = seen homeManagerConfigurations."declared@laptop" // {
                inherit (homeManagerConfigurations."declared@laptop".config.seenLib) parentClass;
              };
              undeclared = seen homeManagerConfigurations."undeclared@laptop";
              selecting = seen homeManagerConfigurations."selecting@laptop";
              insideANixosConfigurationThatSelects = seen homeManagerConfigurations."declared@bare";
              alone = seen homeManagerConfigurations.alone;
            };
          expected = {
            declared = {
              parentNix = "nix-of-the-nixos-configuration";
              parentClass = "nixos";
              homeDirectory = "/home/declared";
              uid = 1001;
              packages = [ "home-manager-cli" ];
              nix = "nix-of-the-nixos-configuration";
              activatedByTheParent = true;
            };
            undeclared = {
              parentNix = "nix-of-the-nixos-configuration";
              homeDirectory = "";
              uid = null;
              packages = [ "home-manager-cli" ];
              nix = "nix-of-the-nixos-configuration";
              activatedByTheParent = true;
            };
            selecting = {
              parentNix = "nix-of-the-nixos-configuration";
              homeDirectory = "";
              uid = null;
              packages = [ ];
              nix = null;
              activatedByTheParent = false;
            };
            insideANixosConfigurationThatSelects = {
              parentNix = "nix-of-the-nixos-configuration";
              homeDirectory = "";
              uid = null;
              packages = [ ];
              nix = null;
              activatedByTheParent = false;
            };
            alone = {
              parentNix = null;
              homeDirectory = "";
              uid = null;
              packages = [ ];
              nix = null;
              activatedByTheParent = false;
            };
          };
        };

      # A NixOS configuration activates the home-manager configurations
      # declared inside it. The `default` NixOS module of caisson
      # imports a module that writes a systemd unit for each such
      # home-manager configuration. The unit is a system unit when the
      # NixOS configuration declares the account of the user of the
      # home-manager configuration in `users.users`. A home-manager
      # configuration whose user has no account there is refused, unless
      # the NixOS configuration lists the user in
      # `caisson.home-manager.activation.usersDeclaredElsewhere`, and
      # then the unit is a user unit.
      #
      # The NixOS configuration `laptop` below has four home-manager
      # configurations. It declares the account of the first. It lists
      # the users of the second and the third as declared elsewhere.
      # The third is declared inside a structural configuration inside
      # `laptop`, and `laptop` activates it too. The fourth is declared
      # inside a second NixOS configuration, `image`, that is declared
      # inside `laptop`. That home-manager configuration belongs to
      # `image`, and `laptop` writes no unit for it.
      #
      # The NixOS configurations `clash`, `stray` and `both` are each
      # refused with a single assertion.
      # `clash` has two home-manager configurations for one user.
      # `stray` has a home-manager configuration whose user has no
      # account and is not listed. `both` lists a user that it also
      # declares.
      "test: a NixOS configuration writes a unit for each home-manager configuration declared inside it" =
        {
          expr =
            let
              lib = flakeLibWith [ "x86_64-linux" ];
              top = lib.caisson.structural.mkTopConfiguration {
                moduleImports = _modules: [ ];
                configModule =
                  { lib, ... }:
                  {
                    caisson.nixos.configurations.laptop = lib.caisson.nixos.mkConfiguration {
                      configModule =
                        { lib, ... }:
                        {
                          users.users.declared.home = "/home/declared";
                          caisson.home-manager.activation.usersDeclaredElsewhere = [
                            "elsewhere"
                            "layered"
                          ];
                          caisson.home-manager.configurations = {
                            declared = homeManagerConfiguration lib { };
                            elsewhere = homeManagerConfiguration lib { };
                          };
                          caisson.structural.configurations.group = lib.caisson.structural.mkConfiguration {
                            moduleImports = _modules: [ ];
                            configModule =
                              { lib, ... }:
                              {
                                caisson.home-manager.configurations.layered = homeManagerConfiguration lib { };
                              };
                          };
                          caisson.nixos.configurations.image = lib.caisson.nixos.mkConfiguration {
                            configModule =
                              { lib, ... }:
                              {
                                users.users.inner.home = "/home/inner";
                                caisson.home-manager.configurations.inner = homeManagerConfiguration lib { };
                              };
                          };
                        };
                    };
                    caisson.nixos.configurations.clash = lib.caisson.nixos.mkConfiguration {
                      configModule =
                        { lib, ... }:
                        {
                          users.users.shared.home = "/home/shared";
                          caisson.home-manager.configurations = {
                            first = homeManagerConfiguration lib { configModule.home.username = "shared"; };
                            second = homeManagerConfiguration lib { configModule.home.username = "shared"; };
                          };
                        };
                    };
                    caisson.nixos.configurations.stray = lib.caisson.nixos.mkConfiguration {
                      configModule =
                        { lib, ... }:
                        {
                          caisson.home-manager.configurations.typo = homeManagerConfiguration lib {
                            configModule.home.username = "nobody";
                          };
                        };
                    };
                    caisson.nixos.configurations.both = lib.caisson.nixos.mkConfiguration {
                      configModule =
                        { lib, ... }:
                        {
                          users.users.twice.home = "/home/twice";
                          caisson.home-manager.activation.usersDeclaredElsewhere = [ "twice" ];
                          caisson.home-manager.configurations.twice = homeManagerConfiguration lib { };
                        };
                    };
                  };
              };
              units = evaluated: {
                system = builtins.attrNames evaluated.config.systemd.services;
                user = builtins.attrNames evaluated.config.systemd.user.services;
                refused = builtins.map (assertion: assertion.message) (
                  builtins.filter (assertion: !assertion.assertion) evaluated.config.assertions
                );
              };
              laptop = units top.nixosConfigurations.laptop;
              image = units top.nixosConfigurations.image;
              # How many assertions of a NixOS configuration fail, and whether the
              # message of the first names each of the words given.
              refusal =
                name: words:
                let
                  inherit (units top.nixosConfigurations.${name}) refused;
                in
                {
                  count = builtins.length refused;
                  names = builtins.all (word: lib.hasInfix word (builtins.head refused)) words;
                };
            in
            {
              inherit laptop image;
              clash = refusal "clash" [
                "shared"
                "first"
                "second"
              ];
              stray = refusal "stray" [
                "typo"
                "nobody"
                "usersDeclaredElsewhere"
              ];
              both = refusal "both" [ "twice" ];
              # A home-manager configuration that is refused gets no
              # unit of either kind.
              strayUnits = {
                inherit (units top.nixosConfigurations.stray) system user;
              };
            };
          expected = {
            laptop = {
              system = [ "home-manager-declared" ];
              user = [
                "home-manager-elsewhere"
                "home-manager-layered"
              ];
              refused = [ ];
            };
            image = {
              system = [ "home-manager-inner" ];
              user = [ ];
              refused = [ ];
            };
            clash = {
              count = 1;
              names = true;
            };
            stray = {
              count = 1;
              names = true;
            };
            both = {
              count = 1;
              names = true;
            };
            strayUnits = {
              system = [ ];
              user = [ ];
            };
          };
        };

      # A NixOS configuration with a home-manager configuration declared
      # inside it writes the file `caisson/marker.json` under `/etc`.
      # The file holds the digest of the store path of the system that
      # the result of the childless evaluation of the NixOS
      # configuration builds.
      #
      # The stub of NixOS puts the number of system units into the
      # store path of a system. The NixOS configuration `laptop` has a
      # home-manager configuration, and `laptop` declares the account
      # of that home-manager configuration. The system of `laptop`
      # therefore has a single unit. The digest in the file must be
      # that of the system with no units.
      #
      # The NixOS configuration `bare` has no home-manager
      # configuration, and writes no file.
      #
      # The NixOS configuration `outer` has a NixOS configuration
      # `image` declared inside it, and `image` has a home-manager
      # configuration. That home-manager configuration belongs to
      # `image`. So `image` writes the file, and `outer` does not:
      # `image` is applied on a different machine, so it checks no
      # marker of `outer`.
      "test: a NixOS configuration with home-manager configurations records the system it runs without them" =
        {
          expr =
            let
              lib = flakeLibWith [ "x86_64-linux" ];
              withHomeManagerConfiguration =
                lib:
                { ... }:
                {
                  users.users.chris.home = "/home/chris";
                  caisson.home-manager.configurations.chris = homeManagerConfiguration lib { };
                };
              top = lib.caisson.structural.mkTopConfiguration {
                moduleImports = _modules: [ ];
                configModule =
                  { lib, ... }:
                  {
                    caisson.nixos.configurations.laptop = lib.caisson.nixos.mkConfiguration {
                      configModule = { lib, ... }: withHomeManagerConfiguration lib { };
                    };
                    caisson.nixos.configurations.bare = lib.caisson.nixos.mkConfiguration {
                      configModule = { };
                    };
                    caisson.nixos.configurations.outer = lib.caisson.nixos.mkConfiguration {
                      configModule =
                        { lib, ... }:
                        {
                          caisson.nixos.configurations.image = lib.caisson.nixos.mkConfiguration {
                            configModule = { lib, ... }: withHomeManagerConfiguration lib { };
                          };
                        };
                    };
                  };
              };
              file = "caisson/marker.json";
              recordOf =
                name:
                let
                  inherit (top.nixosConfigurations.${name}.config.environment) etc;
                in
                if etc ? ${file} then builtins.fromJSON etc.${file}.text else null;
            in
            {
              laptop = recordOf "laptop";
              laptopBuilds = top.nixosConfigurations.laptop.config.system.build.toplevel.outPath;
              bare = recordOf "bare";
              outer = recordOf "outer";
              image = recordOf "image";
            };
          expected = {
            laptop = {
              identity = builtins.hashString "sha256" "/nix/store/stub-system-with-0-units";
            };
            laptopBuilds = "/nix/store/stub-system-with-1-units";
            bare = null;
            outer = null;
            image = {
              identity = builtins.hashString "sha256" "/nix/store/stub-system-with-0-units";
            };
          };
        };

      # The library of a flake has registries: its lib overlays, its
      # modules and its package overlays. A configuration exports the
      # registries, and a configuration also passes up what the
      # configurations declared inside it export.
      #
      # A configuration and the configurations declared inside it
      # share one library, so they hold the same registries. The
      # same entry is therefore given to a configuration twice: once from
      # the configuration itself, and once passed up from a
      # configuration declared inside it. The two are the same entry,
      # and the export holds the entry once.
      #
      # The library below registers lib overlays, one NixOS module
      # and one package overlay. `laptop` is a NixOS configuration
      # with a home-manager configuration declared inside it. The
      # home-manager configuration passes all three registries up to
      # `laptop`, and `laptop` exports each entry once.
      "test: a registry entry passed up from inside a configuration is exported once" = {
        expr =
          let
            lib = flakeLibWith [ "x86_64-linux" ];
            laptopModule =
              { lib, ... }:
              {
                users.users.chris.home = "/home/chris";
                caisson.home-manager.configurations.chris = homeManagerConfiguration lib { };
              };
            top = lib.caisson.structural.mkTopConfiguration {
              moduleImports = _modules: [ ];
              configModule =
                { lib, ... }:
                {
                  caisson.nixos.configurations.laptop = lib.caisson.nixos.mkConfiguration {
                    configModule = laptopModule;
                  };
                };
            };
            inherit (top.nixosConfigurations.laptop.config.caisson) exports;
          in
          {
            # The names alone do not show that an entry merges: the
            # module system merges the definitions of an entry only
            # when the entry is read. So each entry is read as well.
            pkgOverlays = builtins.attrNames exports.pkgOverlays;
            pkgOverlayIsRead = builtins.isFunction exports.pkgOverlays.tools.overlay;
            libOverlayIsRead = builtins.isFunction exports.libOverlays.nixos.overlay;
            nixosModules = builtins.attrNames exports.modules.nixos;
          };
        expected = {
          pkgOverlays = [ "tools" ];
          pkgOverlayIsRead = true;
          libOverlayIsRead = true;
          nixosModules = [ "default" ];
        };
      };

      # Evaluating a NixOS configuration for a system evaluates the
      # configurations declared inside it for that system, so a
      # home-manager configuration declared inside it has an evaluation
      # result for that system alone, and each evaluation result of the
      # NixOS configuration publishes its home-manager configuration. A
      # NixOS configuration that states other systems for the
      # configurations declared inside it
      # (`caisson.forChildren.systems`) holds those configurations for
      # the systems it states.
      "test: a home-manager configuration declared inside a NixOS configuration is evaluated for the system of the NixOS configuration" =
        {
          expr =
            let
              lib = flakeLibWith [
                "x86_64-linux"
                "aarch64-linux"
              ];
              declared = lib.caisson.structural.mkConfiguration {
                moduleImports = _modules: [ ];
                configModule = flakeWith { serving = true; };
              };
              top = lib.caisson-core.finalizeTop declared;
              nixosConfigurations = top.children.system.x86_64-linux.children.nixos;
            in
            {
              systemsInsideTheLaptop = builtins.attrNames nixosConfigurations.laptop.children.system;
              homeManagerConfigurationSystem =
                nixosConfigurations.laptop.children.system.x86_64-linux.children.home-manager.chris.system;
              imagesOfTheServer = builtins.attrNames nixosConfigurations.server.children.system;
              published = builtins.filter (name: lib.hasSuffix "chris@laptop" name) (
                builtins.attrNames
                  (lib.caisson.structural.mkTopConfiguration {
                    moduleImports = _modules: [ ];
                    configModule = flakeWith { serving = true; };
                  }).homeConfigurations
              );
            };
          expected = {
            systemsInsideTheLaptop = [ "x86_64-linux" ];
            homeManagerConfigurationSystem = "x86_64-linux";
            imagesOfTheServer = [ "aarch64-linux" ];
            published = [
              "aarch64-linux/chris@laptop"
              "x86_64-linux/chris@laptop"
            ];
          };
        };

      # How a configuration is published is recorded on its manifest
      # when it is constructed, and applied where it is passed up, so
      # an entry holds the output attribute set, the name and the
      # value. A library that composes neither the nixos nor the
      # home-manager integration publishes such entries: it reads
      # nothing but the entries.
      "test: an entry holds what a caisson top needs to publish it" = {
        expr =
          let
            lib = flakeLibWith [ "x86_64-linux" ];
            top = lib.caisson-core.finalizeTop (
              lib.caisson.structural.mkConfiguration {
                moduleImports = _modules: [ ];
                configModule = flakeWith { serving = false; };
              }
            );
            entries = top.outputs.exports.configurations;
            elsewhere = caisson.mkLib { dependencies = mockDependencies; };
            published = elsewhere.caisson.integrations.publish entries;
          in
          {
            composesNeither = !(elsewhere.caisson ? nixos) && !(elsewhere.caisson ? home-manager);
            recorded = top.children.system.x86_64-linux.children.home-manager.chris.exportsTo.attrset;
            attrsets = builtins.attrNames published;
            homeManagerConfigurations = builtins.attrNames published.homeConfigurations;
            user = published.homeConfigurations."chris@laptop".config.home.username;
            described = builtins.map (entry: entry.description or null) (
              builtins.filter (entry: entry.attrset == "homeConfigurations") entries
            );
          };
        expected = {
          composesNeither = true;
          recorded = "homeConfigurations";
          attrsets = [
            "homeConfigurations"
            "nixosConfigurations"
          ];
          homeManagerConfigurations = [
            "chris"
            "chris@laptop"
            "dana@laptop"
          ];
          user = "chris";
          described = [
            null
            "named chris@laptop from its name and the name of the NixOS configuration it is under"
            "named dana@laptop from its name and the name of the NixOS configuration it is under"
          ];
        };
      };

      # A published name may not contain `/`, which separates the
      # parts of a name, and a home-manager configuration whose name
      # does is refused.
      "test: a home-manager configuration whose published name holds the separator is refused" = {
        expr =
          builtins.attrNames
            ((flakeLibWith [ "x86_64-linux" ]).caisson.structural.mkTopConfiguration {
              moduleImports = _modules: [ ];
              configModule =
                { lib, ... }:
                {
                  caisson.home-manager.configurations."chris/work" = lib.caisson.home-manager.mkConfiguration {
                    configModule = { };
                    check = false;
                  };
                };
            }).homeConfigurations;
        expectedError = {
          type = "ThrownError";
          msg = "named `chris/work`, and a published name may not contain\\s+`/`";
        };
      };
    };

  # The structural integration: the empty integration, evaluating
  # caisson's core module over a composition and returning what the
  # selectors chose.
  structural =
    let
      registeringLib = caisson.mkLib {
        dependencies = mockDependencies;
        modules = callbackLib: {
          flake = {
            thing = callbackLib.caisson.flake-parts.mkModule ({ ... }: { });
            other = callbackLib.caisson.flake-parts.mkModule ({ ... }: { });
          };
          structural = {
            # Each entry stamps `whichEntry` with a marker, so which
            # entry a selection applied is observable in the evaluated
            # configuration.
            default = callbackLib.caisson.structural.mkModule (
              { ... }:
              { lib, ... }:
              {
                options.whichEntry = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                };
                config.whichEntry = "from-the-default";
              }
            );
            # Applied only when selected by name: imported together with
            # the default default it would conflict with the definition
            # above.
            named = callbackLib.caisson.structural.mkModule (
              { ... }:
              { lib, ... }:
              {
                options.whichEntry = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                };
                config.whichEntry = "from-the-registry";
              }
            );
          };
        };
        libOverlays = _lib: {
          provider = mkLibOverlay (
            { ... }:
            {
              overlay = _final: _prev: {
                provided = true;
              };
            }
          );
        };
      };
      # The same composition with a name declared, contributing the
      # namespace of that name to the composed library.
      namespacedLib = caisson.mkLib {
        dependencies = mockDependencies;
        name = "named-composition";
        libOverlays = _lib: {
          named-composition = mkLibOverlay (
            { ... }:
            {
              overlay = _final: prev: {
                named-composition = (prev.named-composition or { }) // {
                  marker = "from-the-namespace-overlay";
                };
              };
            }
          );
        };
      };
      # An option the nested configurations stamp, so which module a
      # configuration evaluated is observable.
      markerOption =
        { lib, ... }:
        {
          options.marker = lib.mkOption { type = lib.types.str; };
        };
      # A composition whose registered configurations nest: the caisson top,
      # found under the name the composition declares, declares `inner`
      # (found under its name) and `plain` (a module passed), and
      # `inner` declares `leaf`, which reads the marker of the
      # configuration it is declared in.
      nestingLib = caisson.mkLib {
        dependencies = mockDependencies;
        name = "nesting";
        configs = callbackLib: {
          structural = {
            nesting = callbackLib.caisson.structural.mkModule (
              { ... }:
              { lib, ... }:
              {
                imports = [ markerOption ];
                marker = "top";
                caisson.structural.configurations.inner = lib.caisson.structural.mkConfiguration { };
                caisson.structural.configurations.plain = lib.caisson.structural.mkConfiguration {
                  configModule = { };
                };
              }
            );
            inner = callbackLib.caisson.structural.mkModule (
              { ... }:
              { lib, ... }:
              {
                imports = [ markerOption ];
                marker = "${lib.caisson-core.evalManifest.name}, registered";
                caisson.structural.configurations.leaf = lib.caisson.structural.mkConfiguration {
                  configModule =
                    { lib, ... }:
                    {
                      imports = [ markerOption ];
                      marker = "leaf inside ${lib.caisson-core.evalManifest.parent.value.config.marker}";
                    };
                };
              }
            );
          };
        };
      };
      selectors =
        { ... }:
        {
          caisson.modules.flake.exported = modules: { inherit (modules) thing; };
          caisson.libOverlays.exported = overlays: { inherit (overlays) provider; };
        };
    in
    {
      "test: a caisson top returns the selected exports with the manifest beside them" = {
        expr =
          let
            top = registeringLib.caisson.structural.mkTopConfiguration {
              configModule = registeringLib.caisson.structural.mkModule selectors;
            };
          in
          {
            modules = builtins.attrNames top.modules.flake;
            libOverlays = builtins.attrNames top.libOverlays;
            hasManifest = top.caisson.manifest ? modules;
          };
        expected = {
          modules = [ "thing" ];
          libOverlays = [ "provider" ];
          hasManifest = true;
        };
      };

      # `caisson.flakeOutputs.modules` selects which exported modules
      # the flake publishes in its `modules` output. This flake
      # publishes none. The exported module `thing` is still in the
      # manifest of the flake, where a flake that lists this flake in
      # `projects` reads it. The `default` entry in the output is the
      # empty module that the `flake` class always has.
      "test: a flake keeps an exported module in the manifest and off the modules output" = {
        expr =
          let
            flake = registeringLib.caisson.flake-parts.mkTopConfiguration {
              configModule = registeringLib.caisson.flake-parts.mkModule (
                { ... }:
                {
                  imports = [ selectors ];
                  systems = [ "x86_64-linux" ];
                  caisson.flakeOutputs.modules = _: { };
                }
              );
              moduleImports = _modules: [ ];
            };
          in
          {
            output = builtins.attrNames flake.modules.flake;
            manifest = builtins.attrNames flake.lib.caisson-core.evalManifest.outputs.exports.modules.flake;
          };
        expected = {
          output = [ "default" ];
          manifest = [ "thing" ];
        };
      };

      "test: flake-parts and structural caisson tops export the same registries" = {
        expr =
          let
            top = registeringLib.caisson.structural.mkTopConfiguration {
              configModule = registeringLib.caisson.structural.mkModule selectors;
            };
            flake = registeringLib.caisson.flake-parts.mkTopConfiguration {
              configModule = registeringLib.caisson.flake-parts.mkModule (
                { ... }:
                {
                  imports = [ selectors ];
                  systems = [ "x86_64-linux" ];
                }
              );
              moduleImports = _modules: [ ];
            };
          in
          {
            sameModules =
              builtins.attrNames flake.modules.flake == [ "default" ] ++ builtins.attrNames top.modules.flake;
            sameOverlays =
              builtins.attrNames flake.lib.caisson-core.evalManifest.outputs.exports.libOverlays
              == builtins.attrNames top.libOverlays;
          };
        expected = {
          sameModules = true;
          sameOverlays = true;
        };
      };

      # The export settings of a class are options that caisson
      # declares for each class of the composition. A setting for a
      # class the composition does not have is refused, and so is a
      # setting a class does not have. Each would otherwise be ignored,
      # and the class would export its default selection.
      "test: an export setting is refused for an unknown class and for an unknown name" = {
        expr =
          let
            evaluates =
              settings:
              (builtins.tryEval (
                builtins.deepSeq (builtins.attrNames
                  (registeringLib.caisson-core.finalizeTop (
                    registeringLib.caisson.structural.mkConfiguration {
                      configModule = {
                        caisson.modules = settings;
                      };
                      moduleImports = _modules: [ ];
                    }
                  )).value.config.caisson.exports.modules
                ) true
              )).success;
          in
          {
            aClassOfTheComposition = evaluates { flake.exported = modules: modules; };
            aMisspelledClass = evaluates { flaek.exported = modules: modules; };
            aMisspelledSetting = evaluates { flake.exportd = modules: modules; };
          };
        expected = {
          aClassOfTheComposition = true;
          aMisspelledClass = false;
          aMisspelledSetting = false;
        };
      };

      "test: the default default applies the entries named default" = {
        expr =
          (registeringLib.caisson-core.finalizeTop (
            registeringLib.caisson.structural.mkConfiguration {
              configModule = { };
            }
          )).value.config.whichEntry;
        expected = "from-the-default";
      };

      "test: a selection by name replaces the default default" = {
        expr =
          (registeringLib.caisson-core.finalizeTop (
            registeringLib.caisson.structural.mkConfiguration {
              configModule = { };
              moduleImports = modules: [ modules.named ];
            }
          )).value.config.whichEntry;
        expected = "from-the-registry";
      };

      # No entry point takes a `name`: a parentless configuration's name
      # is the name declared on mkLib. The pattern of the entry point
      # refuses the argument before the configuration is evaluated, so a `name`
      # can never quietly name the configuration.
      "test: a name argument is refused" = {
        expr = namespacedLib.caisson.structural.mkConfiguration {
          configModule = { };
          moduleImports = _modules: [ ];
          name = "named-top";
        };
        expectedError = unexpectedArgument "mkConfiguration" "name";
      };

      # flake-parts keys an exported module by moduleLocation, which
      # defaults to self.outPath, a rev-sensitive identity. The
      # project's name is rev-independent, so two revisions of one flake
      # key their modules identically and deduplicate rather than
      # colliding on an already-declared option.
      "test: moduleLocation is the declared name, not a store path" = {
        expr =
          let
            mkOutputs =
              tag:
              (caisson.mkLib {
                dependencies = mockDependencies;
                name = "rev-independent";
                modules = callbackLib: {
                  flake = {
                    thing = callbackLib.caisson.flake-parts.mkModule ({ ... }: { });
                  };
                };
              }).caisson.flake-parts.mkTopConfiguration
                {
                  configModule = {
                    systems = [ "x86_64-linux" ];
                    caisson.modules.flake.exported = modules: { inherit (modules) thing; };
                    flake.revTag = tag;
                  };
                  moduleImports = _modules: [ ];
                };
            # flake-parts publishes an exported module as a function, so
            # the stamped identity is read by applying it.
            stamp = outputs: (outputs.modules.flake.thing { })._file;
            first = mkOutputs "one";
            second = mkOutputs "two";
          in
          {
            file = builtins.toString (stamp first);
            # Two evaluation results that differ only in a rev-like fact stamp
            # their exported module the same, which is what lets a
            # consumer composing both deduplicate.
            sameAcrossRevs = builtins.toString (stamp first) == builtins.toString (stamp second);
          };
        expected = {
          file = "rev-independent#modules.flake.thing";
          sameAcrossRevs = true;
        };
      };

      # With no name declared, moduleLocation is not set and
      # flake-parts falls back to its default, derived from `self`.
      # These compositions supply no `self`, so that fallback is
      # observable as flake-parts' complaint rather than as a
      # name-shaped identity.
      "test: a composition declaring no name leaves moduleLocation to flake-parts" = {
        expr =
          let
            outputs =
              (caisson.mkLib {
                dependencies = mockDependencies;
                modules = callbackLib: {
                  flake = {
                    thing = callbackLib.caisson.flake-parts.mkModule ({ ... }: { });
                  };
                };
              }).caisson.flake-parts.mkTopConfiguration
                {
                  configModule = {
                    systems = [ "x86_64-linux" ];
                    caisson.modules.flake.exported = modules: { inherit (modules) thing; };
                  };
                  moduleImports = _modules: [ ];
                };
            stamped = outputs.modules.flake.thing { };
          in
          (builtins.tryEval (builtins.deepSeq stamped._file true)).success;
        expected = false;
      };

      "test: an evaluator argument is refused" = {
        expr = registeringLib.caisson.structural.mkConfiguration {
          configModule = { };
          modules = [ ];
        };
        expectedError = unexpectedArgument "mkConfiguration" "modules";
      };

      "test: ecosystemSrc is refused, the integration wrapping no ecosystem" = {
        expr = registeringLib.caisson.structural.mkConfiguration {
          configModule = { };
          ecosystemSrc = ./.;
        };
        expectedError = unexpectedArgument "mkConfiguration" "ecosystemSrc";
      };

      # Configurations declared inside a structural configuration,
      # under `caisson.structural.configurations`: each is finalized
      # with the attribute it is declared under and the manifest of the
      # result of the childless evaluation of the configuration that
      # declares it, and takes the configuration registered under its
      # name when it passes no module.
      "test: a nested configuration is finalized under its name and the result of its parent's childless evaluation" =
        {
          expr =
            let
              top = nestingLib.caisson-core.finalizeTop (nestingLib.caisson.structural.mkConfiguration { });
              inner = top.children.structural.inner;
              leaf = inner.children.structural.leaf;
            in
            {
              topName = top.name;
              topChildren = builtins.mapAttrs (_: builtins.attrNames) top.children;
              topOption = builtins.attrNames top.value.config.caisson.structural.configurations;
              optionIsTheChild = top.value.config.caisson.structural.configurations.inner.name;
              innerParent = {
                inherit (inner.parent) name childless;
                children = inner.parent.children;
              };
              innerMarker = inner.value.config.marker;
              innerSeesItself = inner.value.config.caisson.manifest.name;
              leafMarker = leaf.value.config.marker;
              leafNearest = leaf.nearest.structural.name;
              leafAncestors = builtins.map (ancestor: ancestor.name) leaf.ancestors;
              plainHasNone = top.children.structural.plain.children;
            };
          expected = {
            topName = "nesting";
            topChildren = {
              structural = [
                "inner"
                "plain"
              ];
            };
            topOption = [
              "inner"
              "plain"
            ];
            optionIsTheChild = "inner";
            innerParent = {
              name = "nesting";
              childless = true;
              children = { };
            };
            innerMarker = "inner, registered";
            innerSeesItself = "inner";
            leafMarker = "leaf inside inner, registered";
            leafNearest = "inner";
            leafAncestors = [
              "nesting"
              "nesting"
              "inner"
            ];
            plainHasNone = { };
          };
        };

      # Re-export: what the configurations declared inside a
      # configuration export is passed up into the exports of the
      # configuration that declares them, nested ones included, and
      # `exported` selects which of them.
      "test: what the configurations declared inside export is passed up" = {
        expr =
          let
            exportsOf =
              exported:
              (registeringLib.caisson-core.finalizeTop (
                registeringLib.caisson.structural.mkConfiguration {
                  moduleImports = _modules: [ ];
                  configModule =
                    { lib, ... }:
                    {
                      caisson.modules.flake.exported = modules: { inherit (modules) thing; };
                      caisson.libOverlays.exported = _overlays: { };
                      caisson.structural.exported = exported;
                      caisson.structural.configurations.middle = lib.caisson.structural.mkConfiguration {
                        moduleImports = _modules: [ ];
                        configModule =
                          { lib, ... }:
                          {
                            caisson.modules.flake.exported = _modules: { };
                            caisson.libOverlays.exported = _overlays: { };
                            caisson.structural.configurations.deep = lib.caisson.structural.mkConfiguration {
                              moduleImports = _modules: [ ];
                              configModule = {
                                caisson.modules.flake.exported = modules: { inherit (modules) other; };
                                caisson.libOverlays.exported = overlays: { inherit (overlays) provider; };
                              };
                            };
                          };
                      };
                    };
                }
              )).outputs.exports;
            names = exports: {
              modules = builtins.attrNames exports.modules.flake;
              libOverlays = builtins.attrNames exports.libOverlays;
            };
          in
          {
            all = names (exportsOf (configurations: configurations));
            none = names (exportsOf (_configurations: { }));
          };
        expected = {
          all = {
            modules = [
              "other"
              "thing"
            ];
            libOverlays = [ "provider" ];
          };
          none = {
            modules = [ "thing" ];
            libOverlays = [ ];
          };
        };
      };

      "test: mkConfigurations declares every registered configuration of the class" = {
        expr = builtins.attrNames (nestingLib.caisson.structural.mkConfigurations { });
        expected = [
          "inner"
          "nesting"
        ];
      };

      # A configuration declared inside another sees the configuration
      # that declares it without the configurations declared inside
      # that configuration. A definition that reads one of them
      # unguarded fails once a configuration declared inside reads the
      # value it defines, and the same definition is readable from the
      # configuration that holds them.
      "test: a nested configuration cannot read a result of the configurations beside it" = {
        expr =
          let
            top = nestingLib.caisson-core.finalizeTop (
              nestingLib.caisson.structural.mkConfiguration {
                configModule =
                  { config, lib, ... }:
                  {
                    imports = [ markerOption ];
                    marker = config.caisson.structural.configurations.quiet.value.config.marker;
                    caisson.structural.configurations.quiet = lib.caisson.structural.mkConfiguration {
                      configModule = {
                        imports = [ markerOption ];
                        marker = "quiet";
                      };
                    };
                    caisson.structural.configurations.reader = lib.caisson.structural.mkConfiguration {
                      configModule =
                        { lib, ... }:
                        {
                          imports = [ markerOption ];
                          marker = lib.caisson-core.evalManifest.parent.value.config.marker;
                        };
                    };
                  };
              }
            );
          in
          {
            fromTheHolder = top.value.config.marker;
            quiet = top.children.structural.quiet.value.config.marker;
            reader = (builtins.tryEval top.children.structural.reader.value.config.marker).success;
          };
        expected = {
          fromTheHolder = "quiet";
          quiet = "quiet";
          reader = false;
        };
      };

      # A user who meets this error needs three facts from it: the option
      # that was read, that the configurations declared inside a
      # configuration read it without the configurations declared
      # inside it, and the guard that keeps a definition out of that
      # evaluation.
      "test: the refusal of a read from inside names the option, the reason and the guard" = {
        expr =
          (nestingLib.caisson-core.finalizeTop (
            nestingLib.caisson.structural.mkConfiguration {
              configModule =
                { config, lib, ... }:
                {
                  imports = [ markerOption ];
                  marker = config.caisson.structural.configurations.quiet.value.config.marker;
                  caisson.structural.configurations.quiet = lib.caisson.structural.mkConfiguration {
                    configModule = {
                      imports = [ markerOption ];
                      marker = "quiet";
                    };
                  };
                  caisson.structural.configurations.reader = lib.caisson.structural.mkConfiguration {
                    configModule =
                      { lib, ... }:
                      {
                        imports = [ markerOption ];
                        marker = lib.caisson-core.evalManifest.parent.value.config.marker;
                      };
                  };
                };
            }
          )).children.structural.reader.value.config.marker;
        expectedError = {
          type = "ThrownError";
          msg = "`caisson\\.structural\\.configurations\\.quiet` was read in the childless evaluation[\\s\\S]*leaves out the configurations declared inside the structural\\s+configuration[\\s\\S]*Guard such a definition with `!lib\\.caisson-core\\.evalManifest\\.childless`";
        };
      };

      "test: what is declared under an integration must be a configuration of that integration" = {
        expr =
          let
            declaring =
              definition:
              (nestingLib.caisson-core.finalizeTop (
                nestingLib.caisson.structural.mkConfiguration {
                  configModule = { lib, ... }: definition lib;
                }
              )).children;
          in
          {
            attrset =
              (builtins.tryEval
                (declaring (_lib: {
                  caisson.structural.configurations.wrong = { };
                })).structural.wrong.name
              ).success;
            otherIntegration =
              (builtins.tryEval
                (declaring (lib: {
                  caisson.flake-parts.configurations.wrong = lib.caisson.structural.mkConfiguration { };
                })).flake-parts.wrong.name
              ).success;
          };
        expected = {
          attrset = false;
          otherIntegration = false;
        };
      };

      # A flake-parts configuration holds the configurations declared
      # inside it as a structural configuration does: each is finalized
      # under its name and the manifest of the result of the childless
      # evaluation of the flake-parts configuration, and what it exports
      # is passed up into the flake outputs.
      "test: a flake-parts configuration holds configurations declared inside it" = {
        expr =
          let
            top = registeringLib.caisson-core.finalizeTop (
              registeringLib.caisson.flake-parts.mkConfiguration {
                configModule =
                  { lib, ... }:
                  {
                    systems = [ "x86_64-linux" ];
                    caisson.modules.flake.exported = _modules: { };
                    caisson.libOverlays.exported = _overlays: { };
                    caisson.structural.configurations.inner = lib.caisson.structural.mkConfiguration {
                      moduleImports = _modules: [ ];
                      configModule = {
                        caisson.modules.flake.exported = modules: { inherit (modules) thing; };
                        caisson.libOverlays.exported = overlays: { inherit (overlays) provider; };
                      };
                    };
                  };
                moduleImports = _modules: [ ];
              }
            );
            inner = top.children.structural.inner;
          in
          {
            type = top.type;
            children = builtins.mapAttrs (_: builtins.attrNames) top.children;
            innerParent = {
              inherit (inner.parent) type childless;
            };
            innerNearest = builtins.attrNames inner.nearest;
            flakeModules = builtins.attrNames top.outputs.flake.modules.flake;
            flakeLibOverlays = builtins.attrNames top.outputs.exports.libOverlays;
            # `mkTopConfiguration` is the finalized configuration's flake
            # outputs.
            topReturnsTheFlakeOutputs =
              let
                args = {
                  configModule = {
                    systems = [ "x86_64-linux" ];
                  };
                  moduleImports = _modules: [ ];
                };
                finalized = registeringLib.caisson-core.finalizeTop (
                  registeringLib.caisson.flake-parts.mkConfiguration args
                );
              in
              builtins.attrNames (registeringLib.caisson.flake-parts.mkTopConfiguration args)
              == builtins.attrNames finalized.outputs.flake;
          };
        expected = {
          type = "flake-parts";
          children = {
            structural = [ "inner" ];
          };
          innerParent = {
            type = "flake-parts";
            childless = true;
          };
          innerNearest = [ "flake-parts" ];
          flakeModules = [
            "default"
            "thing"
          ];
          flakeLibOverlays = [ "provider" ];
          topReturnsTheFlakeOutputs = true;
        };
      };

      # flake-parts' `systems` defaults to the systems the composition
      # declares. For a composition that declares none, the flake
      # evaluates and has no per-system outputs.
      "test: a flake whose composition declares no system has no per-system outputs" = {
        expr =
          let
            outputs =
              (caisson.mkLib { dependencies = mockDependencies; }).caisson.flake-parts.mkTopConfiguration
                {
                  configModule = {
                    perSystem =
                      { ... }:
                      {
                        packages.probe = throw "evaluated with no system";
                      };
                    flake.reached = true;
                  };
                  moduleImports = _modules: [ ];
                };
          in
          {
            inherit (outputs) reached;
            packages = outputs.packages or { };
          };
        expected = {
          reached = true;
          packages = { };
        };
      };

      "test: the WithEcosystemArgs variant evaluates the same call with nothing merged" = {
        expr =
          (registeringLib.caisson-core.finalizeTop (
            registeringLib.caisson.structural.mkConfigurationWithEcosystemArgs {
              configModule = { };
              ecosystemArgs = { };
            }
          )).value.config.whichEntry;
        expected = "from-the-default";
      };
    };

  # The integration constructors: an owner declares a class and its
  # entry points; an alt declares the owner and its entry points.
  # An entry point is a pattern function, so its signature is what Nix
  # matches the call against.
  integrations =
    let
      declaringLib = caisson.mkLib {
        dependencies = mockDependencies;
        libOverlays = _lib: {
          # An owner whose pattern requires nothing.
          probe = mkLibOverlay (
            { ... }:
            {
              overlay =
                final: prev:
                let
                  evaluation = final.caisson.integrations.mkEvaluation {
                    compose = args: {
                      ecosystemArgs = {
                        modules = (args.moduleImports or (_modules: [ ])) (final.caisson.modules.probe or { });
                        tag = args.tag or "none";
                      };
                    };
                    evaluate = _composed: callArgs: callArgs;
                  };
                  integration = final.caisson.integrations.mkIntegration {
                    name = "probe";
                    class = "probe";
                    mkConfiguration =
                      {
                        configModule ? null,
                        moduleImports ? null,
                        tag ? null,
                      }@args:
                      evaluation args;
                    mkConfigurationWithEcosystemArgs =
                      {
                        configModule ? null,
                        moduleImports ? null,
                        tag ? null,
                        ecosystemArgs ? null,
                      }@args:
                      evaluation args;
                    extra = {
                      marker = true;
                    };
                  };
                in
                {
                  caisson = (prev.caisson or { }) // {
                    probe = integration.namespace;
                  };
                };
            }
          );
          probe-alt = mkLibOverlay (
            { ... }:
            {
              overlay =
                final: prev:
                let
                  evaluation = final.caisson.integrations.mkEvaluation {
                    compose = _args: {
                      ecosystemArgs = {
                        alt = true;
                      };
                    };
                    evaluate = _composed: callArgs: callArgs;
                  };
                in
                {
                  caisson = (prev.caisson or { }) // {
                    probe-alt = final.caisson.integrations.mkAltIntegration {
                      over = final.caisson.probe;
                      mkConfiguration =
                        {
                          configModule ? null,
                        }@args:
                        evaluation args;
                      mkConfigurationWithEcosystemArgs =
                        {
                          configModule ? null,
                          ecosystemArgs ? null,
                        }@args:
                        evaluation args;
                    };
                  };
                };
            }
          );
          # An owner whose pattern requires two arguments, those its
          # composition destructures without a default, and an alt over
          # it that requires one.
          probe-strict = mkLibOverlay (
            { ... }:
            {
              overlay =
                final: prev:
                let
                  evaluation = final.caisson.integrations.mkEvaluation {
                    compose =
                      {
                        pkgSets,
                        configModule,
                        ...
                      }:
                      {
                        ecosystemArgs = {
                          inherit pkgSets configModule;
                        };
                      };
                    evaluate = _composed: callArgs: callArgs;
                  };
                  integration = final.caisson.integrations.mkIntegration {
                    name = "probe-strict";
                    class = "probeStrict";
                    mkConfiguration =
                      {
                        configModule,
                        pkgSets,
                        tag ? null,
                      }@args:
                      evaluation args;
                    mkConfigurationWithEcosystemArgs =
                      {
                        configModule,
                        pkgSets,
                        tag ? null,
                        ecosystemArgs ? null,
                      }@args:
                      evaluation args;
                  };
                in
                {
                  caisson = (prev.caisson or { }) // {
                    probe-strict = integration.namespace;
                  };
                };
            }
          );
          probe-strict-alt = mkLibOverlay (
            { ... }:
            {
              overlay =
                final: prev:
                let
                  evaluation = final.caisson.integrations.mkEvaluation {
                    compose = args: {
                      ecosystemArgs = {
                        inherit (args) configModule;
                      };
                    };
                    evaluate = _composed: callArgs: callArgs;
                  };
                in
                {
                  caisson = (prev.caisson or { }) // {
                    probe-strict-alt = final.caisson.integrations.mkAltIntegration {
                      over = final.caisson.probe-strict;
                      mkConfiguration = { configModule }@args: evaluation args;
                      mkConfigurationWithEcosystemArgs =
                        {
                          configModule,
                          ecosystemArgs ? null,
                        }@args:
                        evaluation args;
                    };
                  };
                };
            }
          );
          # An owner and an alt whose compositions throw the moment
          # they are forced, so the error of a refused call shows
          # whether the pattern or the composition fired. The
          # evaluator returns the composition itself, so forcing the
          # result forces the composition through no other route:
          # a merge of the call's arguments forces its operands in
          # an order the Nix version decides.
          probe-forcing = mkLibOverlay (
            { ... }:
            {
              overlay =
                final: prev:
                let
                  evaluation = final.caisson.integrations.mkEvaluation {
                    compose = _args: throw "compose was forced";
                    evaluate = composed: _callArgs: composed;
                  };
                  integration = final.caisson.integrations.mkIntegration {
                    name = "probe-forcing";
                    class = "probeForcing";
                    mkConfiguration = { configModule }@args: evaluation args;
                    mkConfigurationWithEcosystemArgs =
                      {
                        configModule,
                        ecosystemArgs ? null,
                      }@args:
                      evaluation args;
                  };
                in
                {
                  caisson = (prev.caisson or { }) // {
                    probe-forcing = integration.namespace;
                  };
                };
            }
          );
          probe-forcing-alt = mkLibOverlay (
            { ... }:
            {
              overlay =
                final: prev:
                let
                  evaluation = final.caisson.integrations.mkEvaluation {
                    compose = _args: throw "compose was forced";
                    evaluate = composed: _callArgs: composed;
                  };
                in
                {
                  caisson = (prev.caisson or { }) // {
                    probe-forcing-alt = final.caisson.integrations.mkAltIntegration {
                      over = final.caisson.probe-forcing;
                      mkConfiguration = { configModule }@args: evaluation args;
                      mkConfigurationWithEcosystemArgs =
                        {
                          configModule,
                          ecosystemArgs ? null,
                        }@args:
                        evaluation args;
                    };
                  };
                };
            }
          );
        };
      };

      # A stand-in colmena source with the attributes the
      # integration reads, enough to evaluate a colmena configuration
      # whose module reads its node constructors.
      colmenaStub = {
        lib.makeHive = _: {
          __schema = "v0.5";
        };
        nixosModules = {
          deploymentOptions = { };
          assertionModule = { };
          keyChownModule = { };
          keyServiceModule = { };
        };
      };
    in
    {
      "test: an owner has mkModule and the module of its configurations" = {
        expr = {
          hasMkModule = builtins.isFunction declaringLib.caisson.probe.mkModule;
          configurationsModule = declaringLib.caisson.probe.configurationsModule.key;
          marker = declaringLib.caisson.probe.marker;
        };
        expected = {
          hasMkModule = true;
          configurationsModule = "caisson-configurations:probe";
          marker = true;
        };
      };

      "test: the entry points evaluate the composed call and merge ecosystemArgs last" = {
        expr = {
          plain =
            (declaringLib.caisson.probe.mkConfiguration {
              configModule = { };
              tag = "t";
            }).tag;
          open =
            (declaringLib.caisson.probe.mkConfigurationWithEcosystemArgs {
              configModule = { };
              ecosystemArgs.tag = "override";
            }).tag;
        };
        expected = {
          plain = "t";
          open = "override";
        };
      };

      # The pattern of an entry point is its signature: an argument the
      # pattern does not name is Nix's function-argument error,
      # named after the entry point.
      "test: an argument the pattern does not name is refused" = {
        expr = declaringLib.caisson.probe.mkConfiguration {
          configModule = { };
          bogus = 1;
        };
        expectedError = unexpectedArgument "mkConfiguration" "bogus";
      };

      "test: the entry point refuses ecosystemArgs, which the WithEcosystemArgs variant admits" = {
        expr = declaringLib.caisson.probe.mkConfiguration {
          configModule = { };
          ecosystemArgs = { };
        };
        expectedError = unexpectedArgument "mkConfiguration" "ecosystemArgs";
      };

      "test: an alt has entry points and the types of the owner" = {
        expr = {
          names = builtins.attrNames declaringLib.caisson.probe-alt;
          alt = (declaringLib.caisson.probe-alt.mkConfiguration { configModule = { }; }).alt;
        };
        expected = {
          names = [
            "mkConfiguration"
            "mkConfigurationWithEcosystemArgs"
            "types"
          ];
          alt = true;
        };
      };

      # A pattern names the arguments the composition destructures
      # without a default, so a missing argument is Nix's function-argument
      # error, named after the entry point, and not an error from
      # inside the composition. Which of two missing arguments Nix
      # names first is for Nix to decide, so the empty call admits
      # either.
      "test: a missing required argument is reported under the entry point" = {
        expr = declaringLib.caisson.probe-strict.mkConfiguration { };
        expectedError = missingArgument "mkConfiguration" "(configModule|pkgSets)";
      };

      "test: a required argument missing beside the others is reported alone" = {
        expr = declaringLib.caisson.probe-strict.mkConfiguration {
          configModule = { };
        };
        expectedError = missingArgument "mkConfiguration" "pkgSets";
      };

      "test: the WithEcosystemArgs variant requires the same arguments" = {
        expr = declaringLib.caisson.probe-strict.mkConfigurationWithEcosystemArgs {
          ecosystemArgs = { };
        };
        expectedError = missingArgument "mkConfigurationWithEcosystemArgs" "(configModule|pkgSets)";
      };

      "test: an alt requires what its pattern names" = {
        expr = declaringLib.caisson.probe-strict-alt.mkConfiguration { };
        expectedError = missingArgument "mkConfiguration" "configModule";
      };

      "test: an integration requiring nothing takes no arguments at all" = {
        expr = (declaringLib.caisson.probe.mkConfiguration { }).tag;
        expected = "none";
      };

      "test: the arguments a pattern names are accepted" = {
        expr =
          (declaringLib.caisson.probe-strict.mkConfiguration {
            pkgSets = { };
            configModule = { };
          }).configModule;
        expected = { };
      };

      # The pattern is matched before the body exists. The probe's
      # composition throws the moment it is forced, so a refused call
      # that forced it would fail with "compose was forced"; the
      # function-argument error is the proof that it did not.
      "test: a missing argument is refused before the composition is forced" = {
        expr = declaringLib.caisson.probe-forcing.mkConfiguration { };
        expectedError = missingArgument "mkConfiguration" "configModule";
      };

      "test: an unknown argument is refused before the composition is forced" = {
        expr = declaringLib.caisson.probe-forcing.mkConfiguration {
          configModule = { };
          bogus = 1;
        };
        expectedError = unexpectedArgument "mkConfiguration" "bogus";
      };

      "test: the WithEcosystemArgs variant refuses before the composition is forced" = {
        expr = declaringLib.caisson.probe-forcing.mkConfigurationWithEcosystemArgs {
          ecosystemArgs = { };
        };
        expectedError = missingArgument "mkConfigurationWithEcosystemArgs" "configModule";
      };

      "test: an alt refuses before the composition is forced" = {
        expr = declaringLib.caisson.probe-forcing-alt.mkConfiguration { };
        expectedError = missingArgument "mkConfiguration" "configModule";
      };

      # The probe throws when composed, so the tests above are about
      # ordering and not about a composition that never runs.
      "test: an accepted call forces the composition" = {
        expr = builtins.deepSeq (declaringLib.caisson.probe-forcing.mkConfiguration {
          configModule = { };
        }) true;
        expectedError = {
          type = "ThrownError";
          msg = "compose was forced";
        };
      };

      # The integrations the parent registers, as this composition
      # composes them: `builtins.functionArgs` reads each pattern back.
      "test: each WithEcosystemArgs variant takes the arguments of its entry point plus ecosystemArgs" = {
        expr = builtins.listToAttrs (
          builtins.map (name: {
            inherit name;
            value =
              builtins.functionArgs lib.caisson.${name}.mkConfigurationWithEcosystemArgs
              == builtins.functionArgs lib.caisson.${name}.mkConfiguration // { ecosystemArgs = true; };
          }) integrationNames
        );
        expected = builtins.listToAttrs (
          builtins.map (name: {
            inherit name;
            value = true;
          }) integrationNames
        );
      };

      # The entry points whose constructor returns a configuration take
      # `configModule` as optional: each finds the configuration
      # registered under the name of the configuration. The entry points
      # of the configurations evaluated per system take no `pkgSets`:
      # those configurations take their package sets from the
      # composition. The structural, colmena, disko and flake-parts
      # entry points take `pkgSets` and hand it to their modules.
      "test: every entry point takes configModule, optional where it is found by name, and pkgSets where its configurations do not take sets from the composition" =
        {
          expr = builtins.listToAttrs (
            builtins.map (name: {
              inherit name;
              value =
                let
                  signature = builtins.functionArgs lib.caisson.${name}.mkConfiguration;
                  byName = builtins.elem name [
                    "structural"
                    "caisson-colmena"
                    "caisson-disko"
                    "disko"
                    "flake-parts"
                    "nixos"
                    "nixos-minimal"
                    "nixos-test"
                    "darwin"
                    "hjem"
                    "home-manager"
                    "home-manager-minimal"
                    "terranix"
                    "system-manager"
                    "caisson-facter"
                    "facter"
                    "caisson-microvm"
                    "microvm"
                    "caisson-nixops4-composite"
                    "caisson-nixops4-resource"
                    "treefmt"
                    "nvf"
                    "nixvim"
                    "topology"
                    "kubenix"
                    "nixidy"
                  ];
                  setsFromTheComposition = builtins.elem name [
                    "nixos"
                    "nixos-minimal"
                    "nixos-test"
                    "darwin"
                    "hjem"
                    "home-manager"
                    "home-manager-minimal"
                    "terranix"
                    "system-manager"
                    "caisson-facter"
                    "facter"
                    "microvm"
                    "caisson-nixops4-composite"
                    "caisson-nixops4-resource"
                    "treefmt"
                    "nvf"
                    "nixvim"
                    "topology"
                    "kubenix"
                    "nixidy"
                  ];
                in
                signature ? configModule
                && signature.configModule == byName
                && (signature ? pkgSets) == !setsFromTheComposition;
            }) integrationNames
          );
          expected = builtins.listToAttrs (
            builtins.map (name: {
              inherit name;
              value = true;
            }) integrationNames
          );
        };

      "test: mkConfigurationFull takes the arguments of nixos.mkConfiguration" = {
        expr = builtins.functionArgs lib.caisson.nixos.mkConfigurationFull;
        expected = builtins.functionArgs lib.caisson.nixos.mkConfiguration;
      };

      # A colmena configuration declared under the name `colmenaHive` fills
      # the `colmenaHive` of the caisson top it is declared inside, an output
      # that holds a single value: the hive, with the colmena
      # configuration's `meta` and no nodes when no NixOS configuration
      # is declared inside it.
      "test: a colmena configuration named default fills colmenaHive" = {
        expr =
          let
            hive =
              (lib.caisson.structural.mkTopConfiguration {
                moduleImports = _modules: [ ];
                configModule =
                  { lib, ... }:
                  {
                    caisson.caisson-colmena.configurations.colmenaHive = lib.caisson.caisson-colmena.mkConfiguration {
                      ecosystemSrc = _dependencies: colmenaStub;
                      configModule.meta.description = "probe";
                    };
                  };
              }).colmenaHive;
          in
          {
            inherit (hive) __schema nodes;
            inherit (hive.metaConfig) description;
          };
        expected = {
          __schema = "v0.5";
          nodes = { };
          description = "probe";
        };
      };

      # The pattern reads the argument names alone: a value the
      # composition never reads is never forced, whatever it holds.
      "test: the pattern forces the argument names alone" = {
        expr =
          (declaringLib.caisson.probe.mkConfiguration {
            configModule = throw "the value was forced";
            tag = "t";
          }).tag;
        expected = "t";
      };
    };

  # The evaluators of the `homeManager` class: home-manager
  # imports its whole module tree or the necessary modules alone, and
  # that is a choice of how to evaluate, so each way is an entry
  # point. `lib.caisson.home-manager` owns the class and evaluates it
  # with the whole module tree; `lib.caisson.home-manager-minimal` is an alt
  # over it, evaluating the same class with the necessary modules.
  # Both run over the composition the owner publishes, so the two
  # cannot express different profiles from the same arguments.
  #
  # The ecosystem source is a stand-in source tree with the files the
  # integrations read, `modules/lib` (the function composed as the
  # `hm` entry) and `modules/modules.nix` (the module list), each with
  # the signature of the file it stands in for, and
  # `modules/programs.nix` standing for the modules the minimal list
  # drops.
  homeManagerMinimal =
    let
      hmStub = ./home-manager-stub;
      mkCompositionWith =
        sets:
        caisson.mkLib {
          dependencies = mockDependencies // {
            inherit hmStub;
          };
          defaultEcosystemSrc = dependencies: { home-manager = dependencies.hmStub; };
          # A home-manager configuration takes its system and its
          # package set from the composition.
          systems = [ "x86_64-linux" ];
          pkgSets = stubPkgSets sets;
          libOverlays = _lib: {
            home-manager = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/home-manager");
            home-manager-minimal = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/home-manager-minimal");
          };
        };
      myLib = mkCompositionWith { default = { }; };
      # The arguments both entry points take, so the module list is
      # the sole difference between the evaluation results.
      commonArgs = {
        configModule = { };
        check = false;
      };
      whole = myLib.caisson.home-manager.mkTopConfiguration commonArgs;
      necessary = myLib.caisson.home-manager-minimal.mkTopConfiguration commonArgs;
      topOf = declared: myLib.caisson.integrations.topValue (myLib.caisson-core.finalizeTop declared);
    in
    {
      # The alt exists and evaluates the class the other way. The
      # module list home-manager imports is what `minimal` selects, so
      # that is where the entry points part.
      "test: the alt evaluates the class with the necessary modules alone" = {
        expr = {
          owner = {
            inherit (whole.config.stub) minimal moduleList;
          };
          alt = {
            inherit (necessary.config.stub) minimal moduleList;
          };
        };
        expected = {
          owner = {
            minimal = false;
            moduleList = "whole-tree";
          };
          alt = {
            minimal = true;
            moduleList = "necessary";
          };
        };
      };

      # What the difference costs the configuration: an option the
      # dropped modules declare is there under the owner and absent
      # under the alt, which is what makes the entry points different
      # ways of evaluating rather than a single way tuned.
      "test: an option of the dropped modules is absent from the alt" = {
        expr = {
          owner = whole.options ? programs && whole.options.programs ? stub;
          alt = necessary.options.programs ? stub;
        };
        expected = {
          owner = true;
          alt = false;
        };
      };

      # A minimal configuration imports what it uses from
      # `modulesPath`, the special argument the alt supplies.
      "test: the alt supplies modulesPath so a configuration imports for itself" = {
        expr =
          (myLib.caisson.home-manager-minimal.mkTopConfiguration (
            commonArgs
            // {
              configModule =
                { modulesPath, ... }:
                {
                  imports = [ "${modulesPath}/programs.nix" ];
                  programs.stub.enable = true;
                };
            }
          )).config.programs.stub.enable;
        expected = true;
      };

      # The alt has constructors only: the class, its registration
      # form and its composition belong to the integration that owns
      # the class.
      "test: the alt has entry points and the types of the owner" = {
        expr = builtins.attrNames myLib.caisson.home-manager-minimal;
        expected = [
          "mkConfiguration"
          "mkConfigurationWithEcosystemArgs"
          "mkTopConfiguration"
          "types"
        ];
      };

      # The alt takes the arguments of the integration that owns the
      # class, and what it returns is a configuration of that
      # integration: a home-manager configuration, published where
      # home-manager configurations are.
      "test: the alt takes the arguments of the owner and returns a home-manager configuration" = {
        expr = {
          sameArguments =
            builtins.functionArgs myLib.caisson.home-manager-minimal.mkConfiguration
            == builtins.functionArgs myLib.caisson.home-manager.mkConfiguration;
          type =
            (myLib.caisson-core.finalizeTop (myLib.caisson.home-manager-minimal.mkConfiguration commonArgs))
            .x86_64-linux.type;
        };
        expected = {
          sameArguments = true;
          type = "home-manager";
        };
      };

      # `minimal` is not an argument of either entry point: it names
      # the way of evaluating, and each entry point evaluates its way.
      "test: the owner refuses minimal" = {
        expr = myLib.caisson.home-manager.mkConfiguration (commonArgs // { minimal = true; });
        expectedError = unexpectedArgument "mkConfiguration" "minimal";
      };

      "test: the alt refuses minimal" = {
        expr = myLib.caisson.home-manager-minimal.mkConfiguration (commonArgs // { minimal = false; });
        expectedError = unexpectedArgument "mkConfiguration" "minimal";
      };

      # The `WithEcosystemArgs` variant of the alt passes its arguments
      # to the full surface of the evaluator, so the module list can
      # still be replaced outright.
      "test: the WithEcosystemArgs variant of the alt merges ecosystemArgs last" = {
        expr =
          (topOf (
            myLib.caisson.home-manager-minimal.mkConfigurationWithEcosystemArgs (
              commonArgs // { ecosystemArgs.minimal = false; }
            )
          )).config.stub.moduleList;
        expected = "whole-tree";
      };

      # Both entry points use the same composition, so an argument of
      # the class is passed to the alt unchanged.
      "test: the alt composes through the integration that owns the class" = {
        expr =
          (myLib.caisson.home-manager-minimal.mkTopConfiguration (
            commonArgs
            // {
              specialArgs.marker = "from-specialArgs";
              configModule =
                { marker, ... }:
                {
                  news.display = marker;
                };
            }
          )).config.news.display;
        expected = "from-specialArgs";
      };

      # The composition reports a package set it cannot find against
      # the entry point that called it. Here nothing selects, and the
      # composition declares no set named `default`. The package set
      # is read back from the evaluation result, which is where it is
      # selected.
      "test: a missing default package set is reported against the alt" = {
        expr =
          builtins.seq
            ((mkCompositionWith { stable = { }; }).caisson.home-manager-minimal.mkTopConfiguration commonArgs)
            .pkgs
            true;
        expectedError = {
          type = "ThrownError";
          msg = "lib\\.caisson\\.home-manager-minimal\\.mkConfiguration: this home-manager configuration for x86_64-linux runs on the package set named `default`";
        };
      };
    };
}
