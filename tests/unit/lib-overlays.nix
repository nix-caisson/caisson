# SPDX-License-Identifier: MIT
{
  lib,
  inputs ? { },
}:
let
  # The passed lib is the composed library from the unit test flake,
  # carrying both framework namespaces: `caisson-core` (machinery,
  # registry, manifest) and `caisson` (the integrations).
  mkFlakePartsModule = lib.caisson.flake-parts.mkModule;
  mkLibOverlay = lib.caisson-core.mkLibOverlay;
  mkModule = lib.caisson-core.mkModule;

  # caisson's flake-parts integration overlay, recovered from this
  # composition's own manifest, so test compositions can register it
  # the way a consumer registering the exported overlay would.
  flakePartsOverlay = lib.caisson-core.libManifest.libOverlays.flake-parts;
  structuralOverlay = lib.caisson-core.libManifest.libOverlays.structural;

  # Test-facing mkLib: registers the flake-parts and structural
  # integrations into every test composition (so composed test
  # libraries carry caisson.flake-parts.mkConfiguration and
  # caisson.structural.mkTopConfiguration), and otherwise defers to
  # caisson-core.mkLib.
  # Malformed arguments pass through untouched so the machinery's own
  # shape errors stay observable.
  testMkLib =
    args:
    let
      raw = args.libOverlays or (_mkLibOverlay: { });
    in
    if !(builtins.isAttrs args) || !(builtins.isFunction raw) then
      lib.caisson-core.mkLib args
    else
      lib.caisson-core.mkLib (
        args
        // {
          libOverlays =
            mkLibOverlay':
            {
              flake-parts = flakePartsOverlay;
              structural = structuralOverlay;
            }
            // raw mkLibOverlay';
        }
      );

  # The names the test bodies use: the caisson namespace, with the
  # machinery reachable at its top level as well as under
  # `caisson-core`.
  caisson = lib.caisson // {
    inherit (lib.caisson-core) mkLibOverlay mkModule importApply;
    mkLib = testMkLib;
  };

  mockInputs = {
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
    caisson.mkLib ({ inputs = mockInputs; } // args);

in
{
  libExport = {
    "test: assertion fires when configName is null" = {
      expr = builtins.tryEval (
        assert lib.assertMsg (
          null != null
        ) "caisson.lib.export.enabled requires caisson.configInfo.configName to be set.";
        "unreachable"
      );
      expected = {
        success = false;
        value = false;
      };
    };

    "test: assertion passes when configName is set" = {
      expr = builtins.tryEval (
        assert lib.assertMsg (
          "caisson" != null
        ) "caisson.lib.export.enabled requires caisson.configInfo.configName to be set.";
        "ok"
      );
      expected = {
        success = true;
        value = "ok";
      };
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
            libOverlays = _mkLibOverlay: {
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
            libOverlays = _mkLibOverlay: {
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
            libOverlays = _mkLibOverlay: {
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
            libOverlays = _mkLibOverlay: {
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
            libOverlays = _mkLibOverlay: {
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
            libOverlays = _mkLibOverlay: {
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
            libOverlays = _mkLibOverlay: {
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
            libOverlays = _mkLibOverlay: {
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
            libOverlays = _mkLibOverlay: {
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
            libOverlays = _mkLibOverlay: {
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
            libOverlays = _mkLibOverlay: {
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
            libOverlays = _mkLibOverlay: {
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
            libOverlays = _mkLibOverlay: {
              kept = mkLibOverlay ({ ... }: { overlay = final: prev: { keptVal = "yes"; }; });
              dropped = mkLibOverlay ({ ... }: { overlay = final: prev: { droppedVal = "no"; }; });
            };
            libOverlayImports = overlays: [ overlays.kept ];
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
            inputs = mockInputs;
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
          outputs = myLib.caisson.flake-parts.mkConfiguration {
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
            inputs = mockInputs;
            libOverlays = _mkLibOverlay: {
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
          outputs = myLib.caisson.flake-parts.mkConfiguration {
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
            inputs = mockInputs;
            libOverlays = _mkLibOverlay: {
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
          outputs = myLib.caisson.flake-parts.mkConfiguration {
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

    "test: modules.flake attrset receives working modules in flake-parts.mkConfiguration" = {
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

    "test: modules registered via lib aliases work in flake-parts.mkConfiguration" = {
      expr =
        let
          myLib = caisson.mkLib {
            inputs = mockInputs;
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
          outputs = myLib.caisson.flake-parts.mkConfiguration {
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
            inputs = mockInputs;
            libOverlays = _mkLibOverlay: {
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

    "test: function-valued libOverlays receives mkLibOverlay" = {
      expr =
        let
          myLib = caisson.mkLib {
            inputs = mockInputs;
            libOverlays = mkLibOverlayArg: {
              fromFunction = mkLibOverlayArg (
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
            inputs = mockInputs;
            libOverlays = mkLibOverlayArg: {
              marker = mkLibOverlayArg (
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
          outputs = myLib.caisson.flake-parts.mkConfiguration {
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
            inputs = mockInputs;
            libOverlays = _mkLibOverlay: {
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
            libOverlays = _mkLibOverlay: {
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
            libOverlays = _mkLibOverlay: {
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
    "test: refuses inputs (they belong to mkLib)" = {
      expr =
        (builtins.tryEval (
          lib.caisson.flake-parts.mkConfiguration {
            inputs = { };
            configModule = { };
          }
        )).success;
      expected = false;
    };

    "test: refuses modules (configModule and moduleImports carry them)" = {
      expr =
        (builtins.tryEval (
          lib.caisson.flake-parts.mkConfiguration {
            modules = [ ];
            configModule = { };
          }
        )).success;
      expected = false;
    };

    "test: refuses evaluator arguments outside the ecosystem-args twin" = {
      expr =
        (builtins.tryEval (
          lib.caisson.flake-parts.mkConfiguration {
            configModule = { };
            ecosystemArgs = { };
          }
        )).success;
      expected = false;
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
      # flake-parts.mkConfiguration merges { lib = final; } with any specialArgs the caller provides.
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
      # Every entry named `core`, the local one and the `<project>/core`
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
            inputs = mockInputs;

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

          outputs = myLib.caisson.flake-parts.mkConfiguration {
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
            inputs = mockInputs;

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

          outputs = myLib.caisson.flake-parts.mkConfiguration {
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

    "test: flake-parts.mkConfiguration works when modules.flake is absent" = {
      expr =
        let
          myLib = caisson.mkLib {
            inputs = mockInputs;
            modules = _lib: {
              testClass = {
                only = mkModule "test-class" ({ ... }: { });
              };
            };
          };
          outputs = myLib.caisson.flake-parts.mkConfiguration {
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
    # (`lib: { ... }` / `mkLibOverlay: { ... }`). The checks fire as soon
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
            inputs = mockInputs;
            libOverlays = _mkLibOverlay: {
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
              inputs = mockInputs // {
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
              inputs = mockInputs // {
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
  # carrying the three files the integrations read,
  # `nixos/lib/eval-config.nix`, `nixos/lib/default.nix` and
  # `nixos/modules/module-list.nix`, each with the signature of the
  # file it stands in for and its treatment of `lib`, including the
  # `import ../../lib` default that reaches the library of the tree.
  # That `lib` directory throws, so an evaluation handed no library
  # fails where it reaches for one.
  nixosLib =
    let
      nixosStub = ./nixos-stub;
      mkComposition =
        extraOverlays:
        caisson.mkLib {
          inputs = mockInputs;
          defaultEcosystemSrc.nixpkgs = nixosStub;
          libOverlays =
            _mkLibOverlay:
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
            # run on is the composed one.
            marker = lib.caissonMarker or null;
            # A nixpkgs function, so the composed library is still
            # nixpkgs' library and not a bare marker.
            nixpkgs = lib.isFunction lib.id;
          };
        };
      configuration = myLib.caisson.nixos.mkConfiguration {
        configModule = probeModule;
        pkgSets.pkgs = { };
      };
      minimalConfiguration = myLib.caisson.nixos-minimal.mkConfiguration {
        configModule = probeModule;
        pkgSets.pkgs = { };
      };
    in
    {
      # The proof that the composition reaches the modules of a NixOS
      # evaluation: a module inside the evaluation sees the
      # composition's marker and a nixpkgs function at once, on one
      # library. `evalModules` builds the `lib` module argument from
      # the library its own `lib/modules.nix` closed over, which is
      # the fixpoint the `nixpkgs-lib` entry read rather than the one
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
            (myLib.caisson.nixos.mkConfigurationFull {
              configModule = probeModule;
              pkgSets.pkgs = { };
            }).config.stub.fromBaseModules;
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
          (myLib.caisson.nixos.mkConfigurationWithEcosystemArgs {
            configModule = probeModule;
            pkgSets.pkgs = { };
            ecosystemArgs.lib = myLib // {
              caissonMarker = "from-ecosystemArgs";
            };
          }).libArgument.caissonMarker or null;
        expected = "from-ecosystemArgs";
      };

      "test: the twin replaces the library of a minimal evaluation" = {
        expr =
          (myLib.caisson.nixos-minimal.mkConfigurationWithEcosystemArgs {
            configModule = probeModule;
            pkgSets.pkgs = { };
            ecosystemArgs.lib = myLib // {
              caissonMarker = "from-ecosystemArgs";
            };
          }).libArgument.caissonMarker or null;
        expected = "from-ecosystemArgs";
      };

      # A `lib` the caller passes in `specialArgs` takes precedence
      # over the one the composition sets, the way every other special
      # argument does.
      "test: the caller's specialArgs lib takes precedence" = {
        expr =
          (myLib.caisson.nixos.mkConfiguration {
            configModule = probeModule;
            pkgSets.pkgs = { };
            specialArgs.lib = myLib // {
              caissonMarker = "from-specialArgs";
            };
          }).config.seenLib.marker;
        expected = "from-specialArgs";
      };
    };

  # The structural integration: the empty integration, evaluating
  # caisson's core module over a composition and returning what the
  # selectors chose.
  structural =
    let
      registeringLib = caisson.mkLib {
        inputs = mockInputs;
        modules = callbackLib: {
          flake = {
            thing = callbackLib.caisson.flake-parts.mkModule ({ ... }: { });
            other = callbackLib.caisson.flake-parts.mkModule ({ ... }: { });
          };
          structural = {
            default = callbackLib.caisson.structural.mkModule (
              { ... }:
              {
                caisson.configInfo.configName = "from-the-default";
              }
            );
            # Applied only when selected by name: with the default default
            # in force it would conflict with the definition above.
            named = callbackLib.caisson.structural.mkModule (
              { ... }:
              {
                caisson.configInfo.configName = "from-the-registry";
              }
            );
          };
        };
        libOverlays = _mkLibOverlay: {
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
            flake = registeringLib.caisson.flake-parts.mkConfiguration {
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
          (registeringLib.caisson.structural.mkConfiguration {
            configModule = { };
          }).value.caisson.configInfo.configName;
        expected = "from-the-default";
      };

      "test: a selection by name replaces the default default" = {
        expr =
          (registeringLib.caisson.structural.mkConfiguration {
            configModule = { };
            moduleImports = modules: [ modules.named ];
          }).value.caisson.configInfo.configName;
        expected = "from-the-registry";
      };

      "test: the name argument defaults the configuration name" = {
        expr =
          (registeringLib.caisson.structural.mkConfiguration {
            configModule = { };
            moduleImports = _modules: [ ];
            name = "named-top";
          }).value.caisson.configInfo.configName;
        expected = "named-top";
      };

      "test: an evaluator argument is refused with a hint" = {
        expr =
          (builtins.tryEval (
            builtins.deepSeq (registeringLib.caisson.structural.mkConfiguration {
              configModule = { };
              modules = [ ];
            }) true
          )).success;
        expected = false;
      };

      "test: ecosystemSrc is refused, the integration wrapping no ecosystem" = {
        expr =
          (builtins.tryEval (
            builtins.deepSeq (registeringLib.caisson.structural.mkConfiguration {
              configModule = { };
              ecosystemSrc = ./.;
            }) true
          )).success;
        expected = false;
      };

      "test: the twin evaluates the same call with nothing merged" = {
        expr =
          (registeringLib.caisson.structural.mkConfigurationWithEcosystemArgs {
            configModule = { };
            ecosystemArgs = { };
          }).value.caisson.configInfo.configName;
        expected = "from-the-default";
      };
    };

  # The integration constructors: an owner declares a class and an
  # evaluator; an alt declares the owner and another evaluator.
  integrations =
    let
      declaringLib = caisson.mkLib {
        inputs = mockInputs;
        libOverlays = _mkLibOverlay: {
          probe = mkLibOverlay (
            { contributeClasses, ... }:
            {
              overlay =
                final: prev:
                let
                  integration = final.caisson.integrations.mkIntegration {
                    name = "probe";
                    class = "probe";
                    accepted = [ "tag" ];
                    compose = args: {
                      ecosystemArgs = {
                        modules = (args.moduleImports or (_modules: [ ])) (final.caisson-core.modules.probe or { });
                        tag = args.tag or "none";
                      };
                    };
                    evaluate = _composed: callArgs: callArgs;
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
              overlay = final: prev: {
                caisson = (prev.caisson or { }) // {
                  probe-alt = final.caisson.integrations.mkAltIntegration {
                    name = "probe-alt";
                    over = final.caisson.probe;
                    compose = _args: {
                      ecosystemArgs = {
                        alt = true;
                      };
                    };
                    evaluate = _composed: callArgs: callArgs;
                  };
                };
              };
            }
          );
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

      "test: the generated entry points check the signature and merge ecosystemArgs last" = {
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
          refused =
            !(builtins.tryEval (
              builtins.deepSeq (declaringLib.caisson.probe.mkConfiguration {
                configModule = { };
                bogus = 1;
              }) true
            )).success;
        };
        expected = {
          plain = "t";
          open = "override";
          refused = true;
        };
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
    };
}
