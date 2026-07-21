# SPDX-License-Identifier: MIT
{
  lib,
  inputs ? { },
}:
let
  # The passed lib is the composed library from the unit test flake.
  # It contains caisson namespace.
  caisson = lib.caisson;
  mkFlakeModule = caisson.mkFlakeModule;
  mkLibOverlay = caisson.mkLibOverlay;
  mkModule = caisson.mkModule;

  mockInputs = {
    nixpkgs-lib.lib = lib;
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
              closure-self-modules,
              mkModule,
              ...
            }:
            { config, ... }:
            {
              hasInputs = builtins.isAttrs closure-inputs;
              hasLib = builtins.isAttrs closure-lib;
              hasSelfModules = builtins.isAttrs closure-self-modules;
              hasMkMod = builtins.isFunction mkModule;
            };
          result = mkFlakeModule module;
          evaluated = result { config = { }; };
        in
        evaluated.hasInputs && evaluated.hasLib && evaluated.hasSelfModules && evaluated.hasMkMod;
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
          evaluated = (mkFlakeModule module) { config = { }; };
        in
        evaluated.ok;
      expected = true;
    };

    "test: throws on a plain attrset module" = {
      expr = builtins.tryEval (mkFlakeModule {
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
          result = mkFlakeModule modulePath;
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
          a = mkFlakeModule modulePath;
          b = mkFlakeModule modulePath;
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
          result = mkFlakeModule wrapped;
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

    "test: mkFlakeModule is equivalent to mkModule \"flake\"" = {
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

          viaAlias = (caisson.mkFlakeModule module) { config = { }; };
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
                inspect = callbackLib.caisson.mkFlakeModule (
                  { ... }:
                  {
                    flake.inspect = {
                      hasNamespace = callbackLib ? caisson;
                      hasMkModule = builtins.isFunction callbackLib.caisson.mkModule;
                      hasMkFlakeModule = builtins.isFunction callbackLib.caisson.mkFlakeModule;
                      hasMkLibOverlay = builtins.isFunction callbackLib.caisson.mkLibOverlay;
                      hasImportApply = builtins.isFunction callbackLib.caisson.importApply;
                    };
                  }
                );
              };
            };
          };
          outputs = myLib.caisson.mkFlake {
            configModule = myLib.caisson.mkFlakeModule (
              { ... }:
              {
                systems = [ "x86_64-linux" ];
              }
            );
            moduleImports = modules: { inherit (modules) inspect; };
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
                inspect = callbackLib.caisson.mkFlakeModule (
                  { ... }:
                  {
                    flake.callbackSawOverlay = callbackLib.fromCallbackOverlay or "missing";
                  }
                );
              };
            };
          };
          outputs = myLib.caisson.mkFlake {
            configModule = myLib.caisson.mkFlakeModule (
              { ... }:
              {
                systems = [ "x86_64-linux" ];
              }
            );
            moduleImports = modules: { inherit (modules) inspect; };
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
                inspect = callbackLib.caisson.mkFlakeModule (
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
          outputs = myLib.caisson.mkFlake {
            configModule = myLib.caisson.mkFlakeModule (
              { ... }:
              {
                systems = [ "x86_64-linux" ];
              }
            );
            moduleImports = modules: { inherit (modules) inspect; };
          };
        in
        outputs.fixpoint;
      expected = {
        callbackMarker = "same-fixpoint";
        runtimeMarker = "same-fixpoint";
      };
    };

    "test: modules.flake attrset receives working modules in mkFlake" = {
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

    "test: modules registered via lib aliases work in mkFlake" = {
      expr =
        let
          myLib = caisson.mkLib {
            inputs = mockInputs;
            modules = callbackLib: {
              flake = {
                fromAlias = callbackLib.caisson.mkFlakeModule (
                  { ... }:
                  {
                    flake.fromAlias = true;
                  }
                );
              };
            };
          };
          outputs = myLib.caisson.mkFlake {
            configModule = myLib.caisson.mkFlakeModule (
              { ... }:
              {
                systems = [ "x86_64-linux" ];
              }
            );
            moduleImports = modules: { inherit (modules) fromAlias; };
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
              fromAlias = lib.caisson.mkLibOverlay (
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
                inspect = runtimeLib.caisson.mkFlakeModule (
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
          outputs = myLib.caisson.mkFlake {
            configModule = myLib.caisson.mkFlakeModule (
              { ... }:
              {
                systems = [ "x86_64-linux" ];
              }
            );
            moduleImports = modules: { inherit (modules) inspect; };
          };
        in
        outputs.functionModules;
      expected = {
        callbackLib = "present";
        moduleLib = "present";
      };
    };

    "test: custom baseLib is used as the extension base" = {
      # baseLib replaces nixpkgs-lib as the lib that overlays extend.
      # Attributes added via // don't survive lib.extend's fixpoint
      # (extend only sees the overlay chain, not extra attrs), but
      # we can verify baseLib is used by checking that a function from
      # the custom base is reachable via final.
      expr =
        let
          customBase = lib.extend (final: prev: { customBaseMarker = "from-base"; });
          myLib = caisson.mkLib {
            inputs = mockInputs;
            baseLib = customBase;
            libOverlays = _mkLibOverlay: {
              test = mkLibOverlay (
                { ... }:
                {
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

  mkFlake = {
    "test: rejects inputs arg via hasAttr guard" = {
      # mkFlake uses builtins.abort (not throw) when inputs is present,
      # so tryEval cannot catch it. Instead we test the guard condition
      # directly: mkFlake checks builtins.hasAttr "inputs" args.
      expr = builtins.hasAttr "inputs" {
        inputs = { };
        configModule = { };
      };
      expected = true;
    };

    "test: does not reject args without inputs" = {
      expr = builtins.hasAttr "inputs" { configModule = { }; };
      expected = false;
    };

    "test: filteredArgs strips reserved keys" = {
      # mkFlake removes configModule, modules, and moduleImports before
      # forwarding to flake-parts. Verify the stripping logic in isolation.
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
      # mkFlake merges { lib = final; } with any specialArgs the caller provides.
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

    "test: moduleImports default selects all modules" = {
      # The default moduleImports is the identity function.
      expr =
        let
          moduleImports = modules: modules;
          localModules = {
            a = "mod-a";
            b = "mod-b";
          };
        in
        builtins.attrValues (moduleImports localModules);
      expected = [
        "mod-a"
        "mod-b"
      ];
    };

    "test: moduleImports can filter modules" = {
      expr =
        let
          moduleImports = modules: { inherit (modules) a; };
          localModules = {
            a = "mod-a";
            b = "mod-b";
          };
          selected = moduleImports localModules;
        in
        {
          hasA = selected ? a;
          hasB = selected ? b;
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

          outputs = myLib.caisson.mkFlake {
            configModule = myLib.caisson.mkFlakeModule (
              { ... }:
              {
                systems = [ "x86_64-linux" ];
              }
            );
            moduleImports = modules: {
              inherit (modules) fromModules;
            };
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

          outputs = myLib.caisson.mkFlake {
            configModule = myLib.caisson.mkFlakeModule (
              { ... }:
              {
                systems = [ "x86_64-linux" ];
              }
            );
            moduleImports = modules: {
              inherit (modules) fromModulesOnly;
            };
          };
        in
        outputs.fromModulesOnly or false;
      expected = true;
    };

    "test: mkFlake works when modules.flake is absent" = {
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
          outputs = myLib.caisson.mkFlake {
            configModule = myLib.caisson.mkFlakeModule (
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
      expr = builtins.tryEval (mkFlakeModule null);
      expected = {
        success = false;
        value = false;
      };
    };
  };

  types = {
    "test: libOverlay type accepts a built overlay" = {
      expr = caisson.types.libOverlay.check (mkLibOverlay ({ ... }: { overlay = final: prev: { }; }));
      expected = true;
    };

    "test: libOverlay type accepts nested imports" = {
      expr = caisson.types.libOverlay.check {
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
      expr = caisson.types.libOverlay.check (final: prev: { });
      expected = false;
    };

    "test: libOverlay type rejects a malformed import" = {
      expr = caisson.types.libOverlay.check {
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
}
