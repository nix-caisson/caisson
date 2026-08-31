# SPDX-License-Identifier: MIT
{
  libOverlays ? { },
  modules ? { },

  # Extra attrs merged into the closure that mkLibOverlay applies to
  # overlay files; mkLib threads the defining composition's mkModule
  # and the static contributeModules helper through here so overlays
  # can contribute modules closed over their own flake.
  extraOverlayClosure ? { },

  # This closes over the inputs to flake where this overlay is used
  inputs,
}:

# This closes over the inputs to flake where this overlay is defined, i.e. caisson
{ closure-inputs, ... }:

{

  imports = [ ];

  overlay =

    final: prev:
    let

      # Recreate bootLib at this level, so we can use use versions of the functions from this file
      # that close over the inputs of caisson
      bootLib = (
        closure-inputs.nixpkgs-lib.lib.extend (
          (import ./. { inputs = closure-inputs; } { inherit closure-inputs; }).overlay
        )
      );

      # Not using an name@ arg name because doing so leaves off the optional
      # arguments from the bound name
      mkLibArgs = {
        inherit
          inputs
          libOverlays
          modules
          ;
      };

      # The composition calculus and kernel, vendored from caisson-core.
      engine = import ../../vendor/caisson-core/lib;

      # Use a list of lib overlays to extend a lib. Every entry is a built
      # overlay, an `{ imports, overlay }` attrset whose imports are
      # applied before the overlay itself. Composition runs on the
      # caisson-core engine (vendored under vendor/caisson-core; see its
      # PROVENANCE.md): the chain is flattened depth-first, imports before
      # self, duplicates preserved, and applied as anonymous engine
      # entries over the base library, which reproduces the historical
      # fold order exactly. One deliberate contract: the base is
      # contributed as an opaque attribute set, so overriding one of its
      # attributes does not re-tie the base's internal references the way
      # `lib.extend` did.
      mkExtendedLib = (
        let
          flattenOverlay =
            overlay:
            if (builtins.isAttrs overlay) && (builtins.hasAttr "overlay" overlay) then
              (builtins.concatMap flattenOverlay (overlay.imports or [ ]))
              ++ [
                {
                  key = null;
                  imports = [ ];
                  overlay = overlay.overlay;
                }
              ]
            else
              throw ''
                Library overlays are `{ imports, overlay }` attrsets (build them
                with mkLibOverlay, or use another flake's exported overlays), but
                composition encountered a ${builtins.typeOf overlay}.
              '';
        in
        overlays: lib:
        (engine.compose {
          entries = [
            {
              key = null;
              imports = [ ];
              overlay = _final: _prev: lib;
            }
          ]
          ++ builtins.concatMap flattenOverlay overlays;
        }).lib
      );

      mkLibOverlay =
        freeformOverlay:
        (
          # Everything passed to mkLibOverlay takes the closure attrset as its
          # first arg list — `{ closure-inputs, mkLibOverlay, ... }:` — and
          # returns an `{ imports ? [ ], overlay }` attrset. Already-built
          # overlays (e.g. another flake's exported libOverlays) are registered
          # directly, never wrapped in mkLibOverlay.
          let
            requiresImport = (builtins.isPath freeformOverlay) || (builtins.isString freeformOverlay);
            provenance =
              if requiresImport then
                "In lib overlay imported from `${builtins.toString freeformOverlay}`.\n"
              else
                "";
            reified = if requiresImport then import freeformOverlay else freeformOverlay;
            applied =
              if builtins.isFunction reified then
                reified (
                  {
                    closure-inputs = inputs;
                    inherit mkLibOverlay;
                  }
                  // extraOverlayClosure
                )
              else
                throw ''
                  ${provenance}mkLibOverlay expects a function taking the closure attrset
                  (`{ closure-inputs, mkLibOverlay, ... }:`) as its first arg list, but got
                  a ${builtins.typeOf reified}. Register already-built overlays directly
                  instead of wrapping them in mkLibOverlay.
                '';
          in
          if (builtins.isAttrs applied) && (builtins.hasAttr "overlay" applied) then
            {
              imports = applied.imports or [ ];
              overlay = applied.overlay;
            }
          else
            throw ''
              ${provenance}After the closure arg list, a lib overlay is an
              `{ imports ? [ ], overlay }` attrset: put the `final: prev:` function
              under `overlay`, and any overlays it depends on under `imports`. Got
              a ${builtins.typeOf applied} instead.
            ''
        );

      moduleMap =
        f: module:
        (
          let
            requiresImport = (builtins.isPath module) || (builtins.isString module);
            reifiedModule = (if requiresImport then import module else module);
            applied = (
              if
                (
                  (builtins.isAttrs reifiedModule)
                  && (builtins.hasAttr "_file" reifiedModule)
                  && (builtins.hasAttr "imports" reifiedModule)
                  && (builtins.isList reifiedModule.imports)
                  && ((builtins.length reifiedModule.imports) == 1)
                )
              then
                {
                  _file = reifiedModule._file;
                  imports = builtins.map (m: moduleMap f m) reifiedModule.imports;
                }
              else
                f reifiedModule
            );
          in
          (
            if requiresImport then
              {
                _file = module;
                imports = [ applied ];
              }
            else
              applied
          )
        );

      importApply = module: staticArgs: moduleMap (m: m staticArgs) module;

      # Evaluate a consumer-style flake from source with explicitly
      # supplied inputs. The flake's declared inputs resolve by name:
      # `overrides` first, then `follows` chains through the other
      # resolved inputs, then `pool`; anything else throws, naming the
      # input. The self fixpoint and decoration (`inputs`, `outputs`,
      # `outPath`, `_type`) are handled by the shared call-flake kernel.
      # Nothing is fetched: URL-declared inputs must
      # be supplied (test-only pins conventionally come from a
      # tests/dependencies flake). Locks, follows across unsupplied
      # inputs, and sourceInfo are not consulted or emulated.
      callConsumerFlake =
        {
          path,
          pool ? { },
          overrides ? { },
          # forwarded to the self attrset for subjects that read
          # sourceInfo attrs (lastModified, rev, ...)
          sourceInfo ? { },
        }:
        let
          flakeExpr = import (path + "/flake.nix");
          declared = flakeExpr.inputs or { };

          segments = s: builtins.filter (x: builtins.isString x && x != "") (builtins.split "/" s);

          missingFor =
            name: spec:
            throw ''
              callConsumerFlake: input `${name}` of ${builtins.toString path} is declared
              as ${
                if (builtins.isAttrs spec) && (spec ? follows) then
                  "`follows = \"${spec.follows}\"`"
                else if (builtins.isAttrs spec) && (spec ? url) then
                  "`url = \"${spec.url}\"`"
                else
                  "an input"
              } but could not be resolved. Supply it via `pool` or `overrides` —
              nothing is fetched here.
            '';

          followsOrPool =
            name: followsPath:
            let
              segs = segments followsPath;
              headName = builtins.head segs;
              base =
                if builtins.hasAttr headName resolvedDeclared then
                  resolvedDeclared.${headName}
                else
                  pool.${headName} or null;
              step = acc: seg: if acc == null then null else ((acc.inputs or { }).${seg} or null);
              followed = builtins.foldl' step base (builtins.tail segs);
            in
            if followed != null then followed else pool.${name} or (missingFor name { follows = followsPath; });

          resolveName =
            name: spec:
            if builtins.hasAttr name overrides then
              overrides.${name}
            else if (builtins.isAttrs spec) && (spec ? follows) then
              followsOrPool name spec.follows
            else
              pool.${name} or (missingFor name spec);

          resolvedDeclared = builtins.mapAttrs resolveName declared;
        in
        (import ./call-flake.nix) {
          src = path;
          inputs = resolvedDeclared // overrides;
          inherit sourceInfo;
        };

      # Merge module contributions into the registry from inside an
      # overlay body: `overlay = final: prev: contributeModules prev
      # { <class>.<name> = mkModule "<class>" ./m.nix; } // { ... }`.
      # Static on purpose: an overlay's output attribute names must not
      # depend on `final`, so the helper arrives through the overlay
      # closure rather than the composed library.
      contributeModules =
        prev: contributions:
        let
          prevModules = (prev.caisson or { }).modules or { };
        in
        {
          caisson = (prev.caisson or { }) // {
            modules =
              prevModules
              // builtins.mapAttrs (class: names: (prevModules.${class} or { }) // names) contributions;
          };
        };

      mkModuleFor =
        moduleClass:
        let
          mkModule = mkModuleFor moduleClass;
          closureArgs = {
            inherit mkModule;
            closure-inputs = inputs;
            closure-lib = final;
            closure-self-modules = modules.${moduleClass} or { };
          };
        in
        freeformModule:
        (
          # Everything passed to mkModule takes the closure attrset as its first
          # arg list: `{ closure-inputs, closure-lib, closure-self-modules, mkModule, ... }: <module>`.
          let
            applyClosure =
              m:
              if builtins.isFunction m then
                m closureArgs
              else
                throw ''
                  mkModule (class `${moduleClass}`) expects a module function taking the
                  closure attrset (`{ closure-inputs, closure-lib, closure-self-modules, mkModule, ... }:`) as
                  its first arg list, but got a ${builtins.typeOf m}.
                '';
            requiresImport = (builtins.isPath freeformModule) || (builtins.isString freeformModule);
          in
          if requiresImport then
            # `key` mirrors the module system's identity for path imports: the
            # same file passed through mkModule at two sites deduplicates just
            # like importing the same path twice would.
            {
              _file = freeformModule;
              key = builtins.toString freeformModule;
              imports = [ (applyClosure (import freeformModule)) ];
            }
          else
            moduleMap applyClosure freeformModule
        );

      mkFlakeModule = mkModuleFor "flake";

    in
    {

      caisson = (prev.caisson or { }) // {

        mkLib =
          mkLibArgs:
          (
            let
              resolvedArgs = if builtins.isAttrs mkLibArgs then mkLibArgs else throw "mkLib expects an attrset.";

              baseLib = resolvedArgs.baseLib or closure-inputs.nixpkgs-lib.lib;
              inputs = resolvedArgs.inputs;
              mkLibOverlayForInputs = (
                (baseLib.extend
                  (import ./. {
                    inherit inputs;
                    # Lazily bound: overlay files that never contribute
                    # modules never force the composed fixpoint through
                    # these.
                    extraOverlayClosure = {
                      mkModule = finalLib.caisson.mkModule;
                      inherit contributeModules;
                    };
                  } { inherit closure-inputs; }).overlay
                ).caisson.mkLibOverlay
              );
              rawModules = resolvedArgs.modules or (lib: { });
              rawLibOverlays = resolvedArgs.libOverlays or (mkLibOverlay: { });
              modules =
                if builtins.isFunction rawModules then
                  rawModules finalLib
                else
                  throw ''
                    mkLib expects `modules` to be a function taking the composed lib
                    (`lib: { ... }`), but got a ${builtins.typeOf rawModules}. Take
                    the argument and ignore it (`_lib: { ... }`) if you do not need
                    it.
                  '';
              libOverlays =
                if builtins.isFunction rawLibOverlays then
                  rawLibOverlays mkLibOverlayForInputs
                else
                  throw ''
                    mkLib expects `libOverlays` to be a function taking the
                    input-closed mkLibOverlay helper (`mkLibOverlay: { ... }`), but
                    got a ${builtins.typeOf rawLibOverlays}. Take the argument and
                    ignore it (`_mkLibOverlay: { ... }`) if you only register
                    already-built overlays.
                  '';
              libOverlayImports = resolvedArgs.libOverlayImports or (overlays: builtins.attrValues overlays);

              args = {
                inherit baseLib inputs libOverlayImports;
                modules = modules;
                libOverlays = libOverlays;
              };

              coreLibOverlay = mkLibOverlayForInputs (
                (import ./.) {
                  inherit (args)
                    inputs
                    modules
                    libOverlays
                    ;
                  extraOverlayClosure = {
                    mkModule = finalLib.caisson.mkModule;
                    inherit contributeModules;
                  };
                }
              );

              coreLibOverlays = [ coreLibOverlay ];
              # The composing flake's own registrations apply last, so a
              # local name deterministically beats a same-named
              # overlay-borne contribution.
              localModulesOverlay = {
                imports = [ ];
                overlay = _final: prev: contributeModules prev modules;
              };
              finalLib = mkExtendedLib (
                coreLibOverlays ++ importedLibOverlays ++ [ localModulesOverlay ]
              ) baseLib;
              localLibOverlays = args.libOverlays;
              importedLibOverlays = libOverlayImports localLibOverlays;

            in
            # Surface argument-shape errors as soon as the result is used,
            # rather than wherever the offending argument happens to be
            # forced first. `||` only forces the throw-carrying binding in
            # the non-function case.
            builtins.seq (builtins.isFunction rawModules || modules) (
              builtins.seq (builtins.isFunction rawLibOverlays || libOverlays) finalLib
            )
          );

        mkFlake =
          args@{

            configModule,

            moduleImports ? modules: modules,

            # The flake's canonical name. Exported modules are keyed by
            # flake-parts' moduleLocation, which defaults to self.outPath — a
            # rev-sensitive identity, so consumers composing this flake's
            # modules from two different revs (e.g. directly and via a sibling
            # whose lock is one bump behind) collect two copies of the same
            # option declarations and fail with "option ... is already
            # declared". Passing the name here makes module identity
            # rev-independent so such copies deduplicate. Also provides the
            # default for caisson.configInfo.configName, keeping the name
            # single-sourced. It must be an argument rather than (only) module
            # config because moduleLocation is consumed before the module eval
            # exists.
            name ? null,

            ...
          }:
          (
            if builtins.hasAttr "inputs" args then
              builtins.abort "inputs were passed to mkFlake. This is an easy mistake to make, but they should be passed to mkLib."
            else
              let

                filteredArgs = builtins.removeAttrs args [
                  "configModule"
                  "modules"
                  "moduleImports"
                  "name"
                ];

                finalArgs =
                  (if name != null then { moduleLocation = name; } else { })
                  // filteredArgs
                  // {
                    inherit inputs;
                    specialArgs = {
                      lib = final;
                    }
                    // filteredArgs.specialArgs or { };
                  };

                localModules = mkLibArgs.modules // {
                  flake = mkLibArgs.modules.flake or { };
                };
                importedModules = moduleImports localModules.flake;

                coreModule = mkFlakeModule (
                  (importApply ../../modules/flake-parts/core {
                    libOverlays = mkLibArgs.libOverlays;
                    modules = localModules;
                  })
                );

                finalModule = (
                  { lib, ... }:
                  {
                    imports = [
                      coreModule
                    ]
                    ++ (builtins.attrValues importedModules)
                    ++ [ configModule ]
                    ++ (if name != null then [ { caisson.configInfo.configName = lib.mkDefault name; } ] else [ ]);
                  }
                );

              in
              closure-inputs.flake-parts.lib.mkFlake finalArgs finalModule
          );

        inherit
          importApply
          mkLibOverlay
          mkFlakeModule
          callConsumerFlake
          ;

        eval-weight = import ./eval-weight { lib = final; };

        mkMemoizedDerivationRead = import ./mk-memoized-derivation-read.nix { lib = final; };

        partitionExtraInputs = import ./partition-extra-inputs.nix;

        mkModule = mkModuleFor;
        # Seed only: overlay contributions merge in during composition,
        # and mkLib applies the local registrations as a final overlay so
        # the composing flake's own entries win over contributed ones.
        modules = { };

        types = {
          libOverlay =
            let
              isLibOverlay =
                v:
                builtins.isAttrs v
                && builtins.hasAttr "overlay" v
                && builtins.isFunction v.overlay
                && builtins.isList (v.imports or [ ])
                && builtins.all isLibOverlay (v.imports or [ ]);
            in
            final.mkOptionType {
              name = "libOverlay";
              description = "library overlay ({ imports ? [ ], overlay })";
              descriptionClass = "noun";
              check = isLibOverlay;
            };
        };

      };

    };

}
