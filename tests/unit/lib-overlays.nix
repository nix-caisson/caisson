# SPDX-License-Identifier: MIT
{
  lib,
  inputs ? { },
}:
let
  # The passed lib is the composed library from the unit test flake,
  # carrying the framework namespaces: `caisson-core` (machinery,
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
  # libraries carry caisson.flake-parts.mkTopConfiguration and
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

  mockSources = {
    # The real mirror: a tree with lib/ (the nixpkgs-lib entry reads it
    # by input name) whose `lib` is what test bodies read.
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
    caisson.mkLib ({ sources = mockSources; } // args);

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
  # at x86_64-linux is the value given.
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

  # The integrations the parent registers, each with its entry
  # points.
  integrationNames = [
    "nixos"
    "nixos-minimal"
    "home-manager"
    "home-manager-minimal"
    "flake-parts"
    "structural"
    "colmena"
    "terranix"
    "system-manager"
  ];

in
{
  # The default selector for `caisson.lib.exported`: a function of the
  # composed library that looks up the namespace named after the
  # project, the `name` that library's composition declares. These tests apply it to libraries directly, so
  # what they observe is the lookup and nothing around it.
  libExport =
    let
      selectorOf =
        composed:
        (composed.caisson-core.finalizeTop (
          composed.caisson.structural.mkConfiguration {
            configModule = { };
            moduleImports = _modules: [ ];
          }
        )).value.config.caisson.lib.exported;

      # A composition declaring a name and contributing the namespace
      # of that name.
      namedLib = caisson.mkLib {
        sources = mockSources;
        name = "the-namespace";
        libOverlays = _lib: {
          the-namespace = mkLibOverlay (
            { ... }:
            {
              overlay = _final: prev: {
                the-namespace = (prev.the-namespace or { }) // {
                  marker = "selected";
                };
              };
            }
          );
        };
      };

      # The same composition with no name declared.
      unnamedLib = caisson.mkLib { sources = mockSources; };
    in
    {
      "test: the selector reads the namespace off the library it is handed" = {
        expr = (selectorOf namedLib) namedLib;
        expected = {
          marker = "selected";
        };
      };

      # The selector reads the library passed to it, not the library the
      # configuration it came from was evaluated over: handing it another
      # composition's library selects that composition's namespace.
      "test: the selector follows the library, not the configuration it came from" = {
        expr = (selectorOf unnamedLib) namedLib;
        expected = {
          marker = "selected";
        };
      };

      "test: the selector refuses a library whose composition declares no name" = {
        expr = (builtins.tryEval (builtins.deepSeq ((selectorOf namedLib) unnamedLib) true)).success;
        expected = false;
      };
    };

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
              closure-inputs,
              closure-lib,
              mkModule,
              ...
            }:
            { config, ... }:
            {
              hasInputs = builtins.isAttrs closure-inputs;
              hasLib = builtins.isAttrs closure-lib;
              hasMkMod = builtins.isFunction mkModule;
            };
          result = mkFlakePartsModule module;
          evaluated = result { config = { }; };
        in
        evaluated.hasInputs && evaluated.hasLib && evaluated.hasMkMod;
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
              closure-inputs,
              closure-lib,
              mkModule,
              ...
            }:
            { config, ... }:
            {
              hasInputs = builtins.isAttrs closure-inputs;
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
            hasInputs = viaAlias.hasInputs;
            hasLib = viaAlias.hasLib;
            nestedOk = viaAlias.nestedOk.ok or false;
          };
          viaFactory = {
            hasInputs = viaFactory.hasInputs;
            hasLib = viaFactory.hasLib;
            nestedOk = viaFactory.nestedOk.ok or false;
          };
        };
      expected = {
        viaAlias = {
          hasInputs = true;
          hasLib = true;
          nestedOk = true;
        };
        viaFactory = {
          hasInputs = true;
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
          { closure-inputs, ... }:
          {
            overlay = final: prev: { hasPkgs = builtins.hasAttr "nixpkgs-lib" closure-inputs; };
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

  moduleContribution = {
    "test: overlays contribute modules through the closure" = {
      expr =
        let
          myLib = mkTestLib {
            libOverlays = _lib: {
              contrib = mkLibOverlay (
                {
                  mkModule,
                  contributeModules,
                  ...
                }:
                {
                  imports = [ ];
                  overlay =
                    _final: prev:
                    contributeModules prev {
                      nixos.probe = mkModule "nixos" ({ ... }: { config.probe = true; });
                    };
                }
              );
            };
          };
        in
        builtins.attrNames (myLib.caisson-core.modules.nixos or { });
      expected = [ "probe" ];
    };

    "test: contributions merge with argument registrations" = {
      expr =
        let
          myLib = mkTestLib {
            modules = testLib: {
              nixos.local = testLib.caisson-core.mkModule "nixos" ({ ... }: { config.local = true; });
            };
            libOverlays = _lib: {
              contrib = mkLibOverlay (
                {
                  mkModule,
                  contributeModules,
                  ...
                }:
                {
                  imports = [ ];
                  overlay =
                    _final: prev:
                    contributeModules prev {
                      nixos.contributed = mkModule "nixos" ({ ... }: { config.contributed = true; });
                    };
                }
              );
            };
          };
        in
        builtins.attrNames (myLib.caisson-core.modules.nixos or { });
      expected = [
        "contributed"
        "local"
      ];
    };

    "test: contributions ride an overlay's imports chain" = {
      expr =
        let
          contributor = mkLibOverlay (
            {
              mkModule,
              contributeModules,
              ...
            }:
            {
              imports = [ ];
              overlay =
                _final: prev:
                contributeModules prev {
                  homeManager.carried = mkModule "homeManager" ({ ... }: { config.carried = true; });
                };
            }
          );
          myLib = mkTestLib {
            libOverlays = _lib: {
              wrapper = mkLibOverlay (
                { ... }:
                {
                  imports = [ contributor ];
                  overlay = _final: _prev: { };
                }
              );
            };
          };
        in
        builtins.attrNames (myLib.caisson-core.modules.homeManager or { });
      expected = [ "carried" ];
    };

    "test: local registrations win over same-named contributions" = {
      expr =
        let
          myLib = mkTestLib {
            modules = testLib: {
              nixos.shared = testLib.caisson-core.mkModule "nixos" ({ ... }: { config.origin = "local"; });
            };
            libOverlays = _lib: {
              contrib = mkLibOverlay (
                {
                  mkModule,
                  contributeModules,
                  ...
                }:
                {
                  imports = [ ];
                  overlay =
                    _final: prev:
                    contributeModules prev {
                      nixos.shared = mkModule "nixos" ({ ... }: { config.origin = "contributed"; });
                    };
                }
              );
            };
          };
        in
        myLib.caisson-core.modules.nixos.shared.config.origin;
      expected = "local";
    };

    "test: contributeModules composes with namespace contributions" = {
      expr =
        let
          myLib = mkTestLib {
            libOverlays = _lib: {
              contrib = mkLibOverlay (
                {
                  mkModule,
                  contributeModules,
                  ...
                }:
                {
                  imports = [ ];
                  overlay =
                    _final: prev:
                    contributeModules prev {
                      nixos.probe = mkModule "nixos" ({ ... }: { config.probe = true; });
                    }
                    // {
                      probe-ns.marker = "ok";
                    };
                }
              );
            };
          };
        in
        {
          marker = myLib.probe-ns.marker or "missing";
          stillHasMkLib = builtins.isFunction (myLib.caisson-core.mkLib or null);
        };
      expected = {
        marker = "ok";
        stillHasMkLib = true;
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
            libOverlayImports = lib: [ lib.caisson-core.nixpkgs-lib.overlays.kept ];
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
            sources = mockSources;
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
            sources = mockSources;
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
            sources = mockSources;
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
            sources = mockSources;
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
            sources = mockSources;
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
            sources = mockSources;
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
            sources = mockSources;
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

    "test: a registration named nixpkgs-lib replaces the published entry" = {
      # The upstream lib is the published `nixpkgs-lib` entry; a
      # registration under that name replaces it for every overlay
      # that imports it, caisson's integrations included.
      expr =
        let
          myLib = caisson.mkLib {
            sources = mockSources;
            libOverlays = _lib: {
              nixpkgs-lib = mkLibOverlay (
                { ... }:
                {
                  overlay = _final: prev: prev // lib // { customBaseMarker = "from-base"; };
                }
              );
              test = mkLibOverlay (
                { entries, ... }:
                {
                  imports = [ entries.nixpkgs-lib ];
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

    "test: refuses modules (configModule and moduleImports carry them)" = {
      expr = lib.caisson.flake-parts.mkTopConfiguration {
        modules = [ ];
        configModule = { };
      };
      expectedError = unexpectedArgument "mkConfiguration" "modules";
    };

    "test: refuses evaluator arguments outside the ecosystem-args twin" = {
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
            sources = mockSources;

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
            sources = mockSources;

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
            sources = mockSources;
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
      expr = caisson.flake-parts.types.libOverlay.check (
        mkLibOverlay ({ ... }: { overlay = final: prev: { }; })
      );
      expected = true;
    };

    "test: libOverlay type accepts nested imports" = {
      expr = caisson.flake-parts.types.libOverlay.check {
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
      expr = caisson.flake-parts.types.libOverlay.check (final: prev: { });
      expected = false;
    };

    "test: libOverlay type rejects a malformed import" = {
      expr = caisson.flake-parts.types.libOverlay.check {
        imports = [ (final: prev: { }) ];
        overlay = final: prev: { };
      };
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
      # lib.terranixConfiguration, so a stub shows which channel
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
      # registration.
      mkResolutionLib =
        extra:
        caisson.mkLib (
          {
            sources = mockSources;
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
            myLib = mkResolutionLib { defaultEcosystemSrc.terranix = terranixStub "declared"; };
          in
          (myLib.caisson.terranix.mkConfiguration {
            configModule = { };
            pkgSets.pkgs = { };
          }).stubbed;
        expected = "declared";
      };

      "test: an explicit ecosystemSrc beats the declaration" = {
        expr =
          let
            myLib = mkResolutionLib { defaultEcosystemSrc.terranix = terranixStub "declared"; };
          in
          (myLib.caisson.terranix.mkConfiguration {
            ecosystemSrc = terranixStub "explicit";
            configModule = { };
            pkgSets.pkgs = { };
          }).stubbed;
        expected = "explicit";
      };

      "test: an input with the exact name is the last channel" = {
        expr =
          let
            myLib = mkResolutionLib {
              sources = mockSources // {
                terranix = terranixStub "input";
              };
            };
          in
          (myLib.caisson.terranix.mkConfiguration {
            configModule = { };
            pkgSets.pkgs = { };
          }).stubbed;
        expected = "input";
      };

      "test: the declaration beats the exact-name input" = {
        expr =
          let
            myLib = mkResolutionLib {
              sources = mockSources // {
                terranix = terranixStub "input";
              };
              defaultEcosystemSrc.terranix = terranixStub "declared";
            };
          in
          (myLib.caisson.terranix.mkConfiguration {
            configModule = { };
            pkgSets.pkgs = { };
          }).stubbed;
        expected = "declared";
      };

      "test: a full miss throws at the adapter" = {
        expr =
          builtins.tryEval
            ((mkResolutionLib { }).caisson.terranix.mkConfiguration {
              configModule = { };
              pkgSets.pkgs = { };
            }).stubbed;
        expected = {
          success = false;
          value = false;
        };
      };

      "test: declarations join the manifest" = {
        expr =
          let
            myLib = mkResolutionLib { defaultEcosystemSrc.terranix = terranixStub "declared"; };
          in
          (myLib.caisson-core.libManifest.defaultEcosystemSrc.terranix.lib.terranixConfiguration { }).stubbed;
        expected = "declared";
      };
    };

  # The nixos and nixos-minimal integrations: the composed library is
  # the library a NixOS evaluation runs on, threaded into the
  # evaluator of each. The ecosystem source is a stand-in nixpkgs tree
  # carrying the files the integrations read,
  # `nixos/lib/eval-config.nix`, `nixos/lib/default.nix` and
  # `nixos/modules/module-list.nix`, each with the signature of the
  # file it stands in for and its treatment of `lib`, including the
  # `import ../../lib` default that reaches the library of the tree.
  # That `lib` directory throws, so an evaluation handed no library
  # fails where it reaches for a library.
  nixosLib =
    let
      nixosStub = ./nixos-stub;
      mkComposition =
        extraOverlays:
        caisson.mkLib {
          sources = mockSources;
          defaultEcosystemSrc.nixpkgs = nixosStub;
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
              # The marker this composition carries and nothing else
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
      # A composition with a single system in force, a stand-in package
      # config, and a NixOS configuration registered under the name
      # `machine`, which records the name and the system its evaluation
      # carries.
      publishingLib = caisson.mkLib {
        sources = mockSources;
        name = "publishing";
        defaultEcosystemSrc.nixpkgs = nixosStub;
        systems = [ "x86_64-linux" ];
        pkgSets = stubPkgSets { default = { }; };
        libOverlays = _lib: {
          nixos = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/nixos");
        };
        configs = callbackLib: {
          nixos.machine = callbackLib.caisson.nixos.mkModule (
            { ... }:
            { lib, ... }:
            {
              imports = [ probeModule ];
              seenLib.name = lib.caisson-core.evalManifest.name;
              seenLib.at = lib.caisson-core.evalManifest.system;
            }
          );
        };
      };
      # A configuration module that records what the library the
      # module system handed it carries. It declares the option it
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
      # The proof that the composition reaches the modules of a NixOS
      # evaluation: a module inside the evaluation sees the
      # composition's marker and a nixpkgs function at once, on one
      # library. `evalModules` builds the `lib` module argument from
      # the library its `lib/modules.nix` closed over, which is
      # the fixpoint the `nixpkgs-lib` entry read rather than what
      # this composition built, so the marker arrives only because the
      # composition names `lib` among the special arguments.
      "test: the modules of a nixos evaluation see the composed library" = {
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

      # The same library reaches the minimal evaluator, which takes it
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
      # module list of the tree declares is absent from that
      # evaluation, while mkConfigurationFull passes the list
      # explicitly.
      "test: only the full entry point carries the base module list" = {
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

      # The twin replaces the library like any evaluator argument, on
      # both entry points: `eval-config.nix` takes `lib` directly, and
      # the minimal evaluator takes it through the import of
      # `nixos/lib`.
      "test: the twin replaces the library of a nixos evaluation" = {
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

      "test: the twin replaces the library of a minimal evaluation" = {
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

      # A NixOS configuration takes its package set from the
      # composition, at the system the composition declares: the set
      # the `defaultPkgs` argument selects from the available sets, and
      # the set named `default` when nothing selects. Every
      # available set still reaches the modules by config name, as the
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

      # A selection holds for the subtree beneath the configuration
      # that makes it: a configuration that selects nothing runs on
      # what the nearest configuration above it selected, through
      # levels of any integration, and a configuration beneath selects
      # another for itself and what is beneath it. Beside that subtree
      # nothing selects, and a configuration runs on the set named
      # `default`.
      "test: a package set selection holds for everything beneath the configuration that makes it" = {
        expr =
          let
            machine =
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
                    caisson.nixos.configurations.beside = machine lib { };
                    caisson.structural.configurations.group = lib.caisson.structural.mkConfiguration {
                      moduleImports = _modules: [ ];
                      defaultPkgs = pkgSets: pkgSets.other;
                      configModule =
                        { lib, ... }:
                        {
                          caisson.nixos.configurations.inherits = machine lib {
                            configModule =
                              { lib, ... }:
                              {
                                caisson.nixos.configurations.image = machine lib { };
                              };
                          };
                          caisson.nixos.configurations.selects = machine lib {
                            defaultPkgs = pkgSets: pkgSets.default;
                            configModule =
                              { lib, ... }:
                              {
                                caisson.nixos.configurations.image = machine lib { };
                              };
                          };
                        };
                    };
                  };
              }
            );
            machinesOf = manifest: manifest.children.system.x86_64-linux.children.nixos;
            setOf = manifest: manifest.value.config.nixpkgs.pkgs.marker;
            grouped = machinesOf top.children.structural.group;
          in
          {
            beside = setOf (machinesOf top).beside;
            inherits = setOf grouped.inherits;
            beneathInherits = setOf (machinesOf grouped.inherits).image;
            selects = setOf grouped.selects;
            beneathSelects = setOf (machinesOf grouped.selects).image;
          };
        expected = {
          beside = "the default set";
          inherits = "the other set";
          beneathInherits = "the other set";
          selects = "the default set";
          beneathSelects = "the default set";
        };
      };

      # A module of a configuration selects the package set of the
      # configurations beneath it (`caisson.forChildren.defaultPkgs`).
      # The configuration itself runs on the set it was constructed
      # with, and a configuration beneath that is constructed with a
      # selection runs on that.
      "test: a configuration selects the package set of the configurations beneath it" = {
        expr =
          let
            machine =
              lib: args:
              lib.caisson.nixos.mkConfiguration (
                {
                  configModule = { ... }: { };
                }
                // args
              );
            host =
              (myLib.caisson-core.finalizeTop (
                machine myLib {
                  configModule =
                    { lib, ... }:
                    {
                      caisson.forChildren.defaultPkgs = pkgSets: pkgSets.other;
                      caisson.nixos.configurations.image = machine lib {
                        configModule =
                          { lib, ... }:
                          {
                            caisson.nixos.configurations.nested = machine lib { };
                          };
                      };
                      caisson.nixos.configurations.selects = machine lib {
                        defaultPkgs = pkgSets: pkgSets.default;
                      };
                    };
                }
              )).x86_64-linux;
            machinesOf = manifest: manifest.children.system.x86_64-linux.children.nixos;
            setOf = manifest: manifest.value.config.nixpkgs.pkgs.marker;
          in
          {
            host = setOf host;
            image = setOf (machinesOf host).image;
            nested = setOf (machinesOf (machinesOf host).image).nested;
            selects = setOf (machinesOf host).selects;
          };
        expected = {
          host = "the default set";
          image = "the other set";
          nested = "the other set";
          selects = "the default set";
        };
      };

      # Where no configuration from the top down selects, a
      # configuration runs on the set named `default`, and a
      # composition that declares none says so, with the sets it does
      # declare.
      "test: a configuration with no default package set and no selection is refused" = {
        expr =
          let
            noDefault = caisson.mkLib {
              sources = mockSources;
              name = "no-default";
              defaultEcosystemSrc.nixpkgs = nixosStub;
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
          msg = "runs on the package set named `default`,\\s+since no configuration from the top down to it selects one, and the\\s+package sets available here are stable";
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

      # A NixOS configuration is an evaluation for every system in
      # force where it is declared: finalizing it gives its evaluations
      # by system, also when that is a single system, and none when no
      # system is in force. A top read as a tool reads it is the
      # evaluated configuration where there is a single evaluation, and
      # the evaluated configurations by system where there are several.
      "test: a nixos configuration is an evaluation for every system in force" = {
        expr =
          let
            on =
              systems:
              caisson.mkLib {
                sources = mockSources;
                name = "machine";
                defaultEcosystemSrc.nixpkgs = nixosStub;
                inherit systems;
                libOverlays = _lib: {
                  nixos = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/nixos");
                };
              };
            evaluationsOn =
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
            x86 = (evaluationsOn several).x86_64-linux;
          in
          {
            none = builtins.attrNames (evaluationsOn null);
            empty = builtins.attrNames (evaluationsOn [ ]);
            single = builtins.attrNames (evaluationsOn [ "x86_64-linux" ]);
            several = builtins.mapAttrs (_: evaluation: evaluation.value.config.stub.system) (
              evaluationsOn several
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
          name = "machine";
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

      # A NixOS configuration declared beneath another configuration
      # is finalized under the attribute it is declared under, and
      # takes the configuration registered under that name when it
      # passes no module. In the tree its evaluation sits under its
      # name, beneath the system, beneath the configuration that
      # declares it.
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

      # In the tree a configuration of the minimal evaluator is a NixOS
      # configuration: it is declared where NixOS configurations are,
      # has their type, and is published with them.
      "test: a nixos-minimal configuration is declared and published as a nixos configuration" = {
        expr =
          let
            minimalLib = caisson.mkLib {
              sources = mockSources;
              name = "publishing";
              defaultEcosystemSrc.nixpkgs = nixosStub;
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
                  caisson.nixos.configurations.machine = lib.caisson.nixos-minimal.mkConfiguration {
                    configModule = { ... }: { };
                  };
                };
            };
            machine = top.caisson.manifest.children.system.x86_64-linux.children.nixos.machine;
          in
          {
            type = machine.type;
            published = builtins.attrNames top.nixosConfigurations;
            # The minimal evaluator ran: its result has no `system.build`.
            minimal = !(top.nixosConfigurations.machine.config ? system);
          };
        expected = {
          type = "nixos";
          published = [ "machine" ];
          minimal = true;
        };
      };

      "test: a nixos configuration is declared beneath a configuration and found by name" = {
        expr =
          let
            top = publishingLib.caisson-core.finalizeTop (
              publishingLib.caisson.structural.mkConfiguration {
                moduleImports = _modules: [ ];
                configModule =
                  { lib, ... }:
                  {
                    caisson.nixos.configurations.machine = lib.caisson.nixos.mkConfiguration { };
                  };
              }
            );
            system = top.children.system.x86_64-linux;
            machine = system.children.nixos.machine;
          in
          {
            children = builtins.attrNames top.children;
            systems = builtins.attrNames top.children.system;
            systemType = system.type;
            type = machine.type;
            name = machine.value.config.seenLib.name;
            at = machine.value.config.seenLib.at;
            beneath = builtins.map (ancestor: ancestor.type) machine.ancestors;
            nearest = builtins.attrNames machine.nearest;
            outputs = builtins.attrNames machine.outputs;
          };
        expected = {
          children = [ "system" ];
          systems = [ "x86_64-linux" ];
          systemType = "system";
          type = "nixos";
          name = "machine";
          at = "x86_64-linux";
          beneath = [
            "lib"
            "structural"
            "system"
          ];
          nearest = [
            "structural"
            "system"
          ];
          outputs = [
            "exports"
            "images"
            "toplevel"
            "vm"
            "vmWithBootLoader"
          ];
        };
      };

      # Every configuration holds configurations of any integration
      # beneath it. The same module, declaring a configuration of each
      # integration, is the module of a parent of each integration, and
      # every parent holds every one of them.
      "test: a configuration of any integration holds configurations of any integration" = {
        expr =
          let
            beneath =
              { lib, ... }:
              {
                caisson.structural.configurations.group = lib.caisson.structural.mkConfiguration {
                  moduleImports = _modules: [ ];
                };
                caisson.flake-parts.configurations.flake = lib.caisson.flake-parts.mkConfiguration {
                  moduleImports = _modules: [ ];
                };
                caisson.nixos.configurations.machine = lib.caisson.nixos.mkConfiguration {
                  configModule = { ... }: { };
                };
                caisson.nixos.configurations.small = lib.caisson.nixos-minimal.mkConfiguration {
                  configModule = { ... }: { };
                };
              };
            everyLib = caisson.mkLib {
              sources = mockSources;
              name = "publishing";
              defaultEcosystemSrc.nixpkgs = nixosStub;
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
                      configModule = beneath;
                    };
                    caisson.flake-parts.configurations.parent = lib.caisson.flake-parts.mkConfiguration {
                      moduleImports = _modules: [ ];
                      configModule = beneath;
                    };
                    caisson.nixos.configurations.parent = lib.caisson.nixos.mkConfiguration {
                      configModule = beneath;
                    };
                    caisson.nixos.configurations.smallParent = lib.caisson.nixos-minimal.mkConfiguration {
                      configModule = beneath;
                    };
                  };
              }
            );
            held = parent: {
              direct = builtins.mapAttrs (_: builtins.attrNames) (
                builtins.removeAttrs parent.children [ "system" ]
              );
              atSystem = builtins.mapAttrs (_: builtins.attrNames) parent.children.system.x86_64-linux.children;
              # The evaluations beneath are finished evaluations.
              machineIsNixos = parent.children.system.x86_64-linux.children.nixos.machine.value ? config;
            };
            machines = top.children.system.x86_64-linux.children.nixos;
          in
          {
            structural = held top.children.structural.parent;
            flake-parts = held top.children.flake-parts.parent;
            nixos = held machines.parent;
            nixos-minimal = held machines.smallParent;
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
                  "machine"
                  "small"
                ];
              };
              machineIsNixos = true;
            };
          in
          {
            structural = everything;
            flake-parts = everything;
            nixos = everything;
            nixos-minimal = everything;
          };
      };

      # A configuration registers modules for the configurations
      # beneath it and adds to the default selection of a class. They
      # reach a configuration of that class at any depth, through
      # levels of other integrations, and the configuration that
      # registers them does not get them.
      "test: a configuration registers modules for the configurations beneath it" = {
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
            top = publishingLib.caisson-core.finalizeTop (
              publishingLib.caisson.structural.mkConfiguration {
                moduleImports = _modules: [ ];
                configModule =
                  { lib, ... }:
                  {
                    imports = [ (noted "top") ];
                    caisson.forChildren.modules.nixos.site = noted "site";
                    caisson.forChildren.modules.nixos.spare = noted "spare";
                    caisson.forChildren.modules.structural.site = noted "structural site";
                    caisson.forChildren.defaultModuleImports.nixos = lib: [ lib.caisson-core.modules.nixos.site ];
                    caisson.forChildren.defaultModuleImports.structural = lib: [
                      lib.caisson-core.modules.structural.site
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
                          caisson.forChildren.modules.nixos.site = noted "rack site";
                          caisson.nixos.configurations.deep = lib.caisson.nixos.mkConfiguration {
                            configModule = { ... }: { };
                          };
                        };
                    };
                  };
              }
            );
            machines = top.children.system.x86_64-linux.children.nixos;
            rack = top.children.structural.rack;
            deep = rack.children.system.x86_64-linux.children.nixos.deep;
          in
          {
            top = top.value.config.notes;
            direct = machines.direct.value.config.notes;
            chosen = machines.chosen.value.config.notes;
            added = builtins.sort builtins.lessThan machines.added.value.config.notes;
            rack = rack.value.config.notes;
            deep = deep.value.config.notes;
            registryAtTop = builtins.attrNames (top.modules.nixos or { });
            registryBeneath = builtins.attrNames machines.direct.modules.nixos;
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
          deep = [ "rack site" ];
          registryAtTop = [ ];
          registryBeneath = [
            "site"
            "spare"
          ];
        };
      };

      # A configuration reaches the top through every level above it,
      # whatever their integrations: each level passes up what is
      # beneath it. Here a machine sits beneath a machine, beneath a
      # structural configuration, beneath a flake-parts configuration,
      # and the modules of those levels declare configurations and
      # nothing else.
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
                              caisson.nixos.configurations.host = lib.caisson.nixos.mkConfiguration {
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
              top.caisson.manifest.children.flake-parts.site.children.structural.rack.children.system.x86_64-linux.children.nixos.host.children.system.x86_64-linux.children.nixos.image;
          in
          {
            published = builtins.attrNames top.nixosConfigurations;
            # What is published is the evaluation in the tree.
            same = top.nixosConfigurations.image == image.value;
            above = builtins.map (ancestor: ancestor.type) image.ancestors;
          };
        expected = {
          published = [
            "host"
            "image"
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

      # The configurations beneath a NixOS configuration, in the tree
      # and at a top: they are in its manifest, under
      # their system where they are evaluated at one, they see it as
      # the nearest NixOS configuration, and a top publishes them with
      # the others.
      "test: a nixos configuration holds configurations beneath it" = {
        expr =
          let
            top = publishingLib.caisson.structural.mkTopConfiguration {
              moduleImports = _modules: [ ];
              configModule =
                { lib, ... }:
                {
                  caisson.nixos.configurations.host = lib.caisson.nixos.mkConfiguration {
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
            host = top.caisson.manifest.children.system.x86_64-linux.children.nixos.host;
            image = host.children.system.x86_64-linux.children.nixos.image;
          in
          {
            beneath = builtins.attrNames host.children;
            group = host.children.structural.group.type;
            imageName = image.name;
            imageEvaluates = image.value.config.seenLib ? marker;
            imageNearest = image.nearest.nixos.name;
            imageAncestors = builtins.map (ancestor: ancestor.type) image.ancestors;
            published = builtins.attrNames top.nixosConfigurations;
          };
        expected = {
          beneath = [
            "structural"
            "system"
          ];
          group = "structural";
          imageName = "image";
          imageEvaluates = true;
          imageNearest = "host";
          imageAncestors = [
            "lib"
            "structural"
            "system"
            "nixos"
            "system"
          ];
          published = [
            "host"
            "image"
          ];
        };
      };

      # What a top publishes: the NixOS configurations declared beneath
      # it, at any depth, as `nixosConfigurations.<name>`, each the
      # evaluated configuration. The names come from the paths: a name
      # that is alone stays bare, with the system above it and the
      # structural configuration it sits in left out, and the same
      # name in several structural configurations gains their names.
      "test: a top publishes the nixos configurations beneath it under names from their paths" = {
        expr =
          let
            machineIn =
              lib: name:
              lib.caisson.nixos.mkConfiguration {
                configModule = {
                  imports = [ probeModule ];
                  seenLib.name = name;
                };
              };
            group =
              lib: machines:
              lib.caisson.structural.mkConfiguration {
                moduleImports = _modules: [ ];
                configModule =
                  { lib, ... }:
                  {
                    caisson.nixos.configurations = lib.genAttrs machines (machineIn lib);
                  };
              };
            tree =
              { lib, ... }:
              {
                caisson.nixos.configurations.direct = machineIn lib "direct";
                caisson.structural.configurations.a = group lib [
                  "host-1"
                  "host-2"
                ];
                caisson.structural.configurations.b = group lib [ "host-1" ];
              };
            structuralTop = publishingLib.caisson.structural.mkTopConfiguration {
              moduleImports = _modules: [ ];
              configModule = tree;
            };
            flakeTop = publishingLib.caisson.flake-parts.mkTopConfiguration {
              moduleImports = _modules: [ ];
              configModule = {
                imports = [ tree ];
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

      # With several systems in force, a name is published for each
      # evaluation, told apart by the system. `exported` selects what
      # is passed up, and what it leaves out is not published.
      "test: a top publishes an evaluation per system, and only what is selected" = {
        expr =
          let
            severalLib = caisson.mkLib {
              sources = mockSources;
              name = "several";
              defaultEcosystemSrc.nixpkgs = nixosStub;
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
                    caisson.nixos.configurations.machine = lib.caisson.nixos.mkConfiguration {
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
            "aarch64-linux/machine"
            "x86_64-linux/machine"
          ];
          none = false;
        };
      };

      # A `lib` the caller passes in `specialArgs` takes precedence
      # over the `lib` the composition sets, the way every other special
      # argument does.
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

  # The home-manager integration as a library integration: `lib.hm` is
  # an entry of the integration, composed over the library the
  # composition builds, and a home-manager evaluation runs on that
  # library. The ecosystem source is a stand-in tree with the
  # files the integration reads, `modules/lib` (the function composed
  # as the `hm` entry) and `modules/modules.nix` (the module list),
  # each with the signature of the file it stands in for.
  homeManagerLib =
    let
      hmStub = ./home-manager-stub;
      # The same stub at a second path, the store copy of the parent
      # flake: a tree equal in content to the declared tree and
      # different as a tree, so an evaluation can name another
      # home-manager and nothing but the refusal stands in its way.
      hmStubCopy = inputs.parent.outPath + "/tests/unit/home-manager-stub";
      # A home takes its system and its package set from the
      # composition: one system, and a stand-in set named `default`.
      homeComposition = {
        systems = [ "x86_64-linux" ];
        pkgSets = stubPkgSets { default = { }; };
      };
      mkCompositionWith =
        declaration: extraOverlays:
        caisson.mkLib (
          homeComposition
          // {
            sources = mockSources;
            libOverlays =
              _lib:
              {
                home-manager = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/home-manager");
                # The marker this composition carries and nothing else
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
      mkComposition = mkCompositionWith { defaultEcosystemSrc.home-manager = hmStub; };
      myLib = mkComposition { };
      # A composition that declares no home-manager: no
      # `defaultEcosystemSrc.home-manager`, and no input of that name.
      # The tree comes from the `ecosystemSrc` of each evaluation.
      undeclaredLib = mkCompositionWith { } { };
      # A nixpkgs maintainer list for a composition to merge into. The
      # nixpkgs.lib mirror these tests compose on carries none, so a
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
          homeComposition
          // {
            sources = mockSources;
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
      # module system handed it carries.
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
      # A composition for homes in a tree: the systems given, the
      # package configs `default` and `other`, whose set at a system
      # says which it is, NixOS configurations over the stand-in
      # nixpkgs tree, and a home registered under the name `chris`.
      treeLibWith =
        systems:
        caisson.mkLib {
          sources = mockSources;
          name = "homes";
          defaultEcosystemSrc = {
            nixpkgs = ./nixos-stub;
            home-manager = hmStub;
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
                    value.marker = "${config} at ${system}";
                  });
                }
              );
          libOverlays = _lib: {
            home-manager = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/home-manager");
            nixos = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/nixos");
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
      # A tree with a home alone and a machine `laptop` on the set
      # `other` with two homes, the second naming another user and
      # selecting `default`. `serving` adds a machine `server` that
      # holds a configuration for another system.
      home = lib: args: lib.caisson.home-manager.mkConfiguration ({ check = false; } // args);
      treeWith =
        { serving }:
        { lib, ... }:
        {
          caisson.home-manager.configurations.chris = home lib { };
          caisson.nixos.configurations = {
            laptop = lib.caisson.nixos.mkConfiguration {
              defaultPkgs = pkgSets: pkgSets.other;
              configModule =
                { lib, ... }:
                {
                  caisson.home-manager.configurations.chris = home lib { };
                  caisson.home-manager.configurations.dana = home lib {
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
      # A home finalized as a top, read as the home-manager CLI reads
      # it: the evaluated home.
      configuration = myLib.caisson.home-manager.mkTopConfiguration {
        configModule = probeModule;
        check = false;
      };
      # The same for a configuration an entry point with no top form
      # returned.
      topOf =
        composition: declared:
        composition.caisson.integrations.topValue (composition.caisson-core.finalizeTop declared);
    in
    {
      # The proof that the composition reaches the modules: a module
      # inside the evaluation sees the composition's marker and
      # `lib.hm` at once, on one library. Composing `hm` with
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
      "test: lib.maintainers carries both lists" = {
        expr =
          builtins.attrNames
            (mkMaintainersComposition { defaultEcosystemSrc.home-manager = hmStub; }).maintainers;
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

      # The library such an evaluation runs on merges the maintainers
      # of the tree it names, the way the entry does for a declared
      # tree.
      "test: an evaluation naming its home-manager merges its maintainers" = {
        expr =
          ((mkMaintainersComposition { }).caisson.home-manager.mkTopConfiguration {
            ecosystemSrc = hmStub;
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

      # The evaluation composes home-manager's module list from the
      # declared source and hands it `modulesPath`, the special
      # argument home-manager's news entries interpolate. It asks for
      # the list without home-manager's nixpkgs module, so the home
      # runs on the package set it is given.
      "test: the evaluation reads the module list of the declared source" = {
        expr = {
          inherit (configuration.config.stub) minimal useNixpkgsModule;
          # The tail of the path, the head being the store copy of the
          # tree the test flake declared.
          modulesPath = lib.hasSuffix "/home-manager-stub/modules" configuration.config.stub.modulesPath;
        };
        expected = {
          modulesPath = true;
          minimal = false;
          useNixpkgsModule = false;
        };
      };

      # What the evaluation publishes beside the configuration, the
      # names `modules/default.nix` of the home-manager source adds.
      "test: the evaluation publishes the activation package and the news" = {
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

      # The evaluation collects the failed assertions of the
      # configuration and throws with their messages.
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

      "test: the twin replaces the library like any evaluator argument" = {
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

      # An `ecosystemSrc` naming the declared tree names the tree the
      # entry composed `hm` from, and the evaluation runs on the
      # composed library.
      "test: an evaluation naming the declared tree runs on the composed library" = {
        expr =
          (myLib.caisson.home-manager.mkTopConfiguration {
            ecosystemSrc = hmStub;
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

      # A home-manager evaluation runs on one library, so its modules
      # and its `lib.hm` come from one tree. The declared tree composed
      # `hm`; an evaluation naming another tree is refused, with the
      # declaration that would compose an `hm` for it.
      "test: an evaluation naming a second tree beside the declared one is refused" = {
        expr =
          builtins.deepSeq
            (myLib.caisson.home-manager.mkTopConfiguration {
              ecosystemSrc = hmStubCopy;
              configModule = probeModule;
              check = false;
            }).config.seenLib
            true;
        expectedError = {
          type = "ThrownError";
          msg = "as its home-manager, and the composed library carries `lib\\.hm`";
        };
      };

      # With no home-manager declared, the tree an evaluation names
      # supplies its modules and its `lib.hm` both: the modules see
      # the composition's marker and `lib.hm` at once, `hm` calls back
      # through `lib.hm` on the library the evaluation runs on, and the
      # home-manager maintainers are there under `hm`.
      "test: an evaluation names its home-manager when the composition declares none" = {
        expr =
          (undeclaredLib.caisson.home-manager.mkTopConfiguration {
            ecosystemSrc = hmStub;
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

      # Inside such an evaluation, the modules read `lib.hm.dag` the
      # way the modules of home-manager do, and the `lib` option the
      # module list sets to `lib.hm` is that same library.
      "test: the modules of an evaluation naming its home-manager read lib.hm" = {
        expr =
          let
            evaluated = undeclaredLib.caisson.home-manager.mkTopConfiguration {
              ecosystemSrc = hmStub;
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

      # The module system of the evaluation hands out the library the
      # evaluation runs on wherever it creates a module: a submodule
      # and an evaluation run from inside a module both see the
      # composition and `lib.hm`, under a declared home-manager and
      # under a home-manager the evaluation names.
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
            named = seenUnder undeclaredLib { ecosystemSrc = hmStub; };
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

      # With no home-manager declared and none named, there is no tree
      # to evaluate: the miss is reported with the places a tree comes
      # from.
      "test: an evaluation naming no home-manager under no declaration is refused" = {
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

      # A home is a configuration. Declared beneath another
      # configuration it takes the module registered under its name,
      # its user is the name it is declared under unless a module of
      # the home names another, and it runs on the package set in
      # force where it is declared: beneath a NixOS configuration the
      # set of that configuration, unless the home selects. A top
      # publishes it under `homeConfigurations`, named `<user>@<host>`
      # beneath a NixOS configuration and by its name otherwise.
      "test: a home declared beneath a configuration is named, published and given its package set" = {
        expr =
          let
            lib = treeLibWith [ "x86_64-linux" ];
            top = lib.caisson.structural.mkTopConfiguration {
              moduleImports = _modules: [ ];
              configModule = treeWith { serving = false; };
            };
            homes = top.homeConfigurations;
            seen = home: {
              user = home.config.home.username;
              set = home.pkgs.marker;
            };
          in
          {
            names = builtins.attrNames homes;
            alone = seen homes.chris // {
              registered = homes.chris.config.seenLib.registered;
            };
            beneathAMachine = seen homes."chris@laptop";
            selecting = seen homes."dana@laptop";
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
            set = "default at x86_64-linux";
            registered = true;
          };
          beneathAMachine = {
            user = "chris";
            set = "other at x86_64-linux";
          };
          selecting = {
            user = "someone-else";
            set = "default at x86_64-linux";
          };
          aTopHasNoDeclaredName = "";
        };
      };

      # Beneath a NixOS configuration at a system, that system is the
      # one in force, so a home declared there has that evaluation
      # alone, and each evaluation of the machine publishes its home.
      # A machine that states other systems for what is beneath it
      # (`caisson.forChildren.systems`) holds its configurations at
      # those.
      "test: a home beneath a machine is evaluated at the system of the machine" = {
        expr =
          let
            lib = treeLibWith [
              "x86_64-linux"
              "aarch64-linux"
            ];
            declared = lib.caisson.structural.mkConfiguration {
              moduleImports = _modules: [ ];
              configModule = treeWith { serving = true; };
            };
            top = lib.caisson-core.finalizeTop declared;
            machines = top.children.system.x86_64-linux.children.nixos;
          in
          {
            homeOfTheMachine = builtins.attrNames machines.laptop.children.system;
            homeAt = machines.laptop.children.system.x86_64-linux.children.home-manager.chris.system;
            imagesOfTheServer = builtins.attrNames machines.server.children.system;
            published = builtins.filter (name: lib.hasSuffix "chris@laptop" name) (
              builtins.attrNames
                (lib.caisson.structural.mkTopConfiguration {
                  moduleImports = _modules: [ ];
                  configModule = treeWith { serving = true; };
                }).homeConfigurations
            );
          };
        expected = {
          homeOfTheMachine = [ "x86_64-linux" ];
          homeAt = "x86_64-linux";
          imagesOfTheServer = [ "aarch64-linux" ];
          published = [
            "aarch64-linux/chris@laptop"
            "x86_64-linux/chris@laptop"
          ];
        };
      };

      # How a configuration is published is recorded on its manifest
      # when it is constructed, and applied where it is passed up, so
      # an entry carries the output attribute set, the name and the
      # value. A library that composes neither the nixos nor the
      # home-manager integration publishes such entries: it reads
      # nothing but the entries.
      "test: an entry carries all a top needs to publish it" = {
        expr =
          let
            lib = treeLibWith [ "x86_64-linux" ];
            top = lib.caisson-core.finalizeTop (
              lib.caisson.structural.mkConfiguration {
                moduleImports = _modules: [ ];
                configModule = treeWith { serving = false; };
              }
            );
            entries = top.outputs.exports.configurations;
            elsewhere = caisson.mkLib { sources = mockSources; };
            published = elsewhere.caisson.integrations.publish entries;
          in
          {
            composesNeither = !(elsewhere.caisson ? nixos) && !(elsewhere.caisson ? home-manager);
            recorded = top.children.system.x86_64-linux.children.home-manager.chris.exportsTo.attrset;
            attrsets = builtins.attrNames published;
            homes = builtins.attrNames published.homeConfigurations;
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
          homes = [
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
      # parts of a name, and a home whose name does is refused.
      "test: a home whose published name holds the separator is refused" = {
        expr =
          builtins.attrNames
            ((treeLibWith [ "x86_64-linux" ]).caisson.structural.mkTopConfiguration {
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
        sources = mockSources;
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
            # Applied only when selected by name: with the default default
            # in force it would conflict with the definition above.
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
      # namespace of that name to the composed library, so what the lib
      # export selects is observable beside the composition that
      # declares none.
      namespacedLib = caisson.mkLib {
        sources = mockSources;
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
      # A composition whose registered configurations nest: the top,
      # found under the name the composition declares, declares `inner`
      # (found under its name) and `plain` (a module passed), and
      # `inner` declares `leaf`, which reads the marker of the
      # configuration it is declared in.
      nestingLib = caisson.mkLib {
        sources = mockSources;
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
                      marker = "leaf beneath ${lib.caisson-core.evalManifest.parent.value.config.marker}";
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
      "test: a top returns the selected exports with the manifest beside them" = {
        expr =
          let
            top = registeringLib.caisson.structural.mkTopConfiguration {
              configModule = registeringLib.caisson.structural.mkModule selectors;
            };
          in
          {
            modules = builtins.attrNames top.modules.flake;
            libOverlays = builtins.attrNames top.libOverlays;
            lib = top.lib;
            hasManifest = top.caisson.manifest ? modules;
          };
        expected = {
          modules = [ "thing" ];
          libOverlays = [ "provider" ];
          lib = { };
          hasManifest = true;
        };
      };

      "test: the flake top and the structural top export the same registries" = {
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
            sameOverlays = builtins.attrNames flake.libOverlays == builtins.attrNames top.libOverlays;
          };
        expected = {
          sameModules = true;
          sameOverlays = true;
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

      # The lib export reader: the namespace it selects comes from the
      # composed library it is handed, so declaring a name on mkLib is
      # the whole of what decides which namespace gets published.
      "test: the lib export selects the namespace named after the declared name" = {
        expr =
          (namespacedLib.caisson-core.finalizeTop (
            namespacedLib.caisson.structural.mkConfiguration {
              configModule = {
                caisson.lib.export.enabled = true;
              };
              moduleImports = _modules: [ ];
            }
          )).value.config.caisson.exports.lib;
        expected = {
          marker = "from-the-namespace-overlay";
        };
      };

      # Declaring none is a state the tree supports, up to the point
      # something asks for a name. The lib export is such a reader, and
      # what it produces is the message, not a missing attribute.
      "test: the lib export refuses a composition that declares no name" = {
        expr =
          (builtins.tryEval (
            builtins.deepSeq
              (registeringLib.caisson-core.finalizeTop (
                registeringLib.caisson.structural.mkConfiguration {
                  configModule = {
                    caisson.lib.export.enabled = true;
                  };
                  moduleImports = _modules: [ ];
                }
              )).value.config.caisson.exports.lib
              true
          )).success;
        expected = false;
      };

      # Nothing asking for a name is the ordinary case for a composition
      # that declares none: the evaluation goes through.
      "test: a composition declaring no name evaluates without one" = {
        expr =
          (registeringLib.caisson-core.finalizeTop (
            registeringLib.caisson.structural.mkConfiguration {
              configModule = { };
              moduleImports = _modules: [ ];
            }
          )).value.config.caisson.exports.lib;
        expected = { };
      };

      # No entry point takes a `name`: a parentless configuration's name
      # is the name declared on mkLib. The pattern of the entry point
      # refuses the argument before the evaluation exists, so a `name`
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
                sources = mockSources;
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
            # Two evaluations that differ only in a rev-like fact stamp
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
                sources = mockSources;
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

      # Configurations declared beneath a structural configuration,
      # under `caisson.structural.configurations`: each is finalized
      # with the attribute it is declared under and the childless
      # manifest of the configuration that declares it, and takes the
      # configuration registered under its name when it passes no
      # module.
      "test: a configuration declared beneath is finalized under its name and the childless parent" = {
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
          leafMarker = "leaf beneath inner, registered";
          leafNearest = "inner";
          leafAncestors = [
            "nesting"
            "nesting"
            "inner"
          ];
          plainHasNone = { };
        };
      };

      # Re-export: what the configurations declared beneath export is
      # passed up into the exports of the configuration that declares
      # them, at every depth, and `exported` selects which of them.
      "test: what the configurations beneath export is passed up" = {
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

      # A configuration beneath sees the configuration that declares it
      # without the configurations declared beneath it. A definition that
      # reads one of them unguarded fails once a configuration beneath
      # reads the value it defines, and the same definition is readable
      # from the configuration that holds them.
      "test: a configuration beneath cannot read a result of the configurations beside it" = {
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

      "test: what is declared beneath must be a configuration of that integration" = {
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

      # A flake-parts evaluation holds configurations beneath it as a
      # structural evaluation does: each is finalized under its name and the
      # childless manifest of the flake evaluation, and what it exports
      # is passed up into the flake outputs.
      "test: a flake-parts evaluation holds configurations beneath it" = {
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
            flakeLibOverlays = builtins.attrNames top.outputs.flake.libOverlays;
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
      # declares. A composition that declares none has no system in
      # force, so the flake evaluates and has no per-system outputs.
      "test: a flake with no system in force has no per-system outputs" = {
        expr =
          let
            outputs = (caisson.mkLib { sources = mockSources; }).caisson.flake-parts.mkTopConfiguration {
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

      "test: the twin evaluates the same call with nothing merged" = {
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
        sources = mockSources;
        libOverlays = _lib: {
          # An owner whose pattern requires nothing.
          probe = mkLibOverlay (
            { contributeClasses, ... }:
            {
              overlay =
                final: prev:
                let
                  evaluation = final.caisson.integrations.mkEvaluation {
                    compose = args: {
                      ecosystemArgs = {
                        modules = (args.moduleImports or (_modules: [ ])) (final.caisson-core.modules.probe or { });
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
                contributeClasses prev integration.classes
                // {
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
            { contributeClasses, ... }:
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
                contributeClasses prev integration.classes
                // {
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
            { contributeClasses, ... }:
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
                contributeClasses prev integration.classes
                // {
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
      "test: an owner declares its class in the index and carries mkModule" = {
        expr = {
          integration = declaringLib.caisson-core.classes.probe.integration;
          hasMkModule = builtins.isFunction declaringLib.caisson.probe.mkModule;
          marker = declaringLib.caisson.probe.marker;
        };
        expected = {
          integration = "probe";
          hasMkModule = true;
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

      "test: the entry point refuses ecosystemArgs, which the twin admits" = {
        expr = declaringLib.caisson.probe.mkConfiguration {
          configModule = { };
          ecosystemArgs = { };
        };
        expectedError = unexpectedArgument "mkConfiguration" "ecosystemArgs";
      };

      "test: an alt carries entry points only" = {
        expr = {
          names = builtins.attrNames declaringLib.caisson.probe-alt;
          alt = (declaringLib.caisson.probe-alt.mkConfiguration { configModule = { }; }).alt;
        };
        expected = {
          names = [
            "mkConfiguration"
            "mkConfigurationWithEcosystemArgs"
          ];
          alt = true;
        };
      };

      # A pattern names the arguments the composition destructures
      # without a default, so a missing argument is Nix's function-argument
      # error, named after the entry point, and never an error from
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

      "test: the twin requires the same arguments" = {
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
      # that reached it would fail with "compose was forced"; the
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

      "test: the twin refuses before the composition is forced" = {
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
      "test: an accepted call reaches the composition" = {
        expr = builtins.deepSeq (declaringLib.caisson.probe-forcing.mkConfiguration {
          configModule = { };
        }) true;
        expectedError = {
          type = "ThrownError";
          msg = "compose was forced";
        };
      };

      # The integrations the parent registers, as this composition
      # carries them: `builtins.functionArgs` reads each pattern back.
      "test: every twin takes the arguments of its entry point plus ecosystemArgs" = {
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
      # registered under the name of the configuration. The nixos and
      # home-manager entry points take no `pkgSets`: a NixOS
      # configuration and a home take their package sets from the
      # composition.
      "test: every entry point takes configModule, optional where it is found by name, and pkgSets except on nixos and home-manager" =
        {
          expr = builtins.listToAttrs (
            builtins.map (name: {
              inherit name;
              value =
                let
                  signature = builtins.functionArgs lib.caisson.${name}.mkConfiguration;
                  byName = builtins.elem name [
                    "structural"
                    "flake-parts"
                    "nixos"
                    "nixos-minimal"
                    "home-manager"
                    "home-manager-minimal"
                  ];
                  setsFromTheComposition = builtins.elem name [
                    "nixos"
                    "nixos-minimal"
                    "home-manager"
                    "home-manager-minimal"
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

      # The node constructors a colmena configuration receives forward
      # to the nixos entry points, and their patterns are the same, so
      # a wrong argument is reported under the constructor's name.
      "test: the colmena node constructors take the arguments of the nixos entry points" = {
        expr =
          let
            hive = lib.caisson.colmena.mkConfiguration {
              ecosystemSrc = colmenaStub;
              configModule =
                { mkNixosConfiguration, mkNixosConfigurationWithEcosystemArgs, ... }:
                {
                  meta.description = builtins.toJSON {
                    # A node names its module, where a NixOS
                    # configuration may take the configuration
                    # registered under its name; the argument names
                    # are the same.
                    node =
                      builtins.attrNames (builtins.functionArgs mkNixosConfiguration)
                      == builtins.attrNames (builtins.functionArgs lib.caisson.nixos.mkConfiguration);
                    twin =
                      builtins.attrNames (builtins.functionArgs mkNixosConfigurationWithEcosystemArgs)
                      == builtins.attrNames (builtins.functionArgs lib.caisson.nixos.mkConfigurationWithEcosystemArgs);
                    requiresItsModule = !(builtins.functionArgs mkNixosConfiguration).configModule;
                  };
                };
            };
          in
          builtins.fromJSON hive.metaConfig.description;
        expected = {
          node = true;
          twin = true;
          requiresItsModule = true;
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
  # that is a choice between evaluations, so each way is an entry
  # point. `lib.caisson.home-manager` owns the class and evaluates it
  # with the whole tree; `lib.caisson.home-manager-minimal` is an alt
  # over it, evaluating the same class with the necessary modules.
  # Both run over the composition the owner publishes, so the two
  # cannot express different profiles from the same arguments.
  #
  # The ecosystem source is a stand-in tree with the files the
  # integrations read, `modules/lib` (the function composed as the
  # `hm` entry) and `modules/modules.nix` (the module list), each with
  # the signature of the file it stands in for, and
  # `modules/programs.nix` standing for the tree the minimal list
  # drops.
  homeManagerMinimal =
    let
      hmStub = ./home-manager-stub;
      mkCompositionWith =
        sets:
        caisson.mkLib {
          sources = mockSources;
          defaultEcosystemSrc.home-manager = hmStub;
          # A home takes its system and its package set from the
          # composition.
          systems = [ "x86_64-linux" ];
          pkgSets = stubPkgSets sets;
          libOverlays = _lib: {
            home-manager = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/home-manager");
            home-manager-minimal = mkLibOverlay (inputs.parent.outPath + "/lib-overlays/home-manager-minimal");
          };
        };
      myLib = mkCompositionWith { default = { }; };
      # The arguments both entry points take, so the module list is
      # the sole difference between the evaluations.
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
      # dropped tree declares is there under the owner and absent
      # under the alt, which is what makes the two different
      # evaluations rather than one evaluation tuned.
      "test: an option of the dropped tree is absent from the alt" = {
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
      # `modulesPath`, the special argument the evaluation supplies.
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

      # The alt carries constructors only: the class, its registration
      # form and its composition belong to the integration that owns
      # the class.
      "test: the alt carries entry points only" = {
        expr = builtins.attrNames myLib.caisson.home-manager-minimal;
        expected = [
          "mkConfiguration"
          "mkConfigurationWithEcosystemArgs"
          "mkTopConfiguration"
        ];
      };

      # The class is declared by the integration that owns it.
      "test: the alt declares no class" = {
        expr = myLib.caisson-core.classes.homeManager.integration;
        expected = "home-manager";
      };

      # The alt takes the arguments of the integration that owns the
      # class, and what it returns is a configuration of that
      # integration: a home, published where homes are.
      "test: the alt takes the arguments of the owner and returns a home" = {
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
      # the evaluation, and each entry point evaluates its way.
      "test: the owner refuses minimal" = {
        expr = myLib.caisson.home-manager.mkConfiguration (commonArgs // { minimal = true; });
        expectedError = unexpectedArgument "mkConfiguration" "minimal";
      };

      "test: the alt refuses minimal" = {
        expr = myLib.caisson.home-manager-minimal.mkConfiguration (commonArgs // { minimal = false; });
        expectedError = unexpectedArgument "mkConfiguration" "minimal";
      };

      # The twin of the alt reaches the evaluator's full surface, so
      # the module list can still be replaced outright.
      "test: the twin of the alt merges ecosystemArgs last" = {
        expr =
          (topOf (
            myLib.caisson.home-manager-minimal.mkConfigurationWithEcosystemArgs (
              commonArgs // { ecosystemArgs.minimal = false; }
            )
          )).config.stub.moduleList;
        expected = "whole-tree";
      };

      # The same composition serves both entry points, so an argument of
      # the class reaches the alt unchanged.
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
      # is read back from the evaluation, which is where it is
      # selected.
      "test: a missing default package set is reported against the alt" = {
        expr =
          builtins.seq
            ((mkCompositionWith { stable = { }; }).caisson.home-manager-minimal.mkTopConfiguration commonArgs)
            .pkgs
            true;
        expectedError = {
          type = "ThrownError";
          msg = "lib\\.caisson\\.home-manager-minimal\\.mkConfiguration: this home at x86_64-linux runs on the package set named `default`";
        };
      };
    };
}
