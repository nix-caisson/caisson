# SPDX-License-Identifier: MIT
#
# The home-manager integration: it owns the `homeManager` class,
# contributes the declared home-manager's library to the composition
# as `lib.hm`, and evaluates the class over the composed library with
# home-manager's module list. A home is a configuration: it is
# evaluated at every system in force where it is declared, on the
# package set in force there, and a top publishes it under
# `homeConfigurations`. Beside the entry points the integration
# carries the adapters that place a home inside a NixOS configuration,
# and the source metadata the activation coherence check compares.
{
  contributeClasses,
  mkLibOverlay,
  ...
}:
{

  imports = [
    # The library of nixpkgs, which this overlay calls through the
    # composed library, imported by key so it is composed wherever
    # this is.
    ((mkLibOverlay ../nixpkgs-lib) // { key = "nixpkgs-lib"; })
    # What an integration is written from, imported by key so it is
    # composed wherever this integration is.
    ((mkLibOverlay ../integrations) // { key = "integrations"; })
  ];

  overlay =
    final: prev:
    let
      mkModule = final.caisson.home-manager.mkModule;
      mkNixosModule = final.caisson-core.mkModule "nixos";

      selection = final.caisson.integrations;
      # What the adapters share out of the registry of the class, as
      # the composition holds it: every registered `core`.
      registry = final.caisson-core.modules.homeManager or { };
      coreModules = selection.coreModules registry;

      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc {
        name = "home-manager";
        context = "caisson.home-manager";
      };
      resolveSrc =
        explicit:
        resolveEcosystemSrc {
          inherit explicit;
          manifest = final.caisson-core.libManifest or { };
        };

      resolveOutPath =
        value:
        if value == null then
          null
        else if builtins.isAttrs value && value ? outPath then
          value.outPath
        else
          toString value;

      # The home-manager this composition declares:
      # `defaultEcosystemSrc.home-manager` of the mkLib call, else the
      # pinned source of that name; null when it declares none. The layered
      # lookup of the integrations entry, read without its miss
      # message: a composition may leave the tree to the
      # `ecosystemSrc` of each evaluation.
      declaredSrc =
        let
          manifest = final.caisson-core.libManifest or { };
        in
        resolveOutPath (
          final.caisson-core.resolve {
            name = "home-manager";
            defaults = manifest.defaultEcosystemSrc or { };
            sources = manifest.sources or { };
          }
        );

      # home-manager's library over a library: `modules/lib/default.nix`
      # of the tree at `src` applied to `lib`. Its functions call each
      # other through `lib.hm`, so the library they are applied to
      # carries the result as `hm`, and every nixpkgs name they read
      # is a name that library has.
      mkHmLib = src: lib: import "${src}/modules/lib" { inherit lib; };

      # The declared home-manager's library over the composed library,
      # the `hm` entry this integration contributes; forced only when
      # read. Reading it in a composition that declares no
      # home-manager names the places a tree comes from.
      hmLibDeclared =
        if declaredSrc != null then
          mkHmLib declaredSrc final
        else
          throw ''
            lib.hm: this composition declares no home-manager. Declare it as
            `defaultEcosystemSrc.home-manager` in the mkLib call, or pin a
            source named `home-manager` in the `sources` passed to mkLib; an evaluation
            that names its home-manager through `ecosystemSrc` runs on the
            composed library carrying `hm` from that tree.
          '';

      # The library an evaluation runs on: the composed library with
      # the module system tied over it. The module system hands `lib`
      # to every module it evaluates, those of the main evaluation
      # through `specialArgs` and the rest, submodules and the
      # evaluations home-manager's tree runs beside the main evaluation
      # (the manual's option documentation), from the library the module
      # system's files closed over. The module system of the composed
      # library is what nixpkgs built, closed over the nixpkgs
      # fixpoint, which has none of what the composition contributed.
      # Applying `extend` to that fixpoint re-ties the nixpkgs library
      # over a new fixpoint, and the library the modules run on takes its
      # `modules`, `types` and `evalModules` from that re-tied copy, so
      # every module the evaluation creates, however deep, receives
      # this library, with `lib.hm` and everything the composition
      # contributed. The result is extensible, and an `extend` over it
      # (which the `docs/default.nix` of home-manager applies) keeps all
      # of it.
      #
      # `base` is the library of the view being evaluated, the
      # composed library carrying the manifest of the evaluation.
      #
      # `hmSrc` names the tree `hm` comes from when the composition
      # declares none: `hm` and the home-manager maintainers merged
      # into the nixpkgs list are then built over this library, the
      # way the entries below build them over the composed library, so
      # the `lib.hm` calls inside `hm` resolve to this `hm`. With null
      # the composed library carries `hm` already, as the entry.
      mkEvaluationLib =
        base: hmSrc:
        base.extend (
          self: super:
          base
          // {
            inherit (super) modules types evalModules;
          }
          // final.optionalAttrs (hmSrc != null) {
            hm = (prev.hm or { }) // mkHmLib hmSrc self;
            maintainers = (prev.maintainers or { }) // self.hm.maintainers;
          }
        );

      # A home-manager evaluation runs on one library, so its modules
      # and its `lib.hm` come from one tree. With a declared
      # home-manager, the composed library carries `hm` from that tree
      # as an entry, and an evaluation whose `ecosystemSrc` names a
      # different tree is refused, the message naming the declaration
      # that composes an `hm` for it. With none declared, the tree the
      # evaluation names supplies both.
      libFor =
        base: explicit:
        let
          named = resolveOutPath (resolveSrc explicit);
        in
        if declaredSrc == null then
          mkEvaluationLib base named
        else if explicit == null || named == declaredSrc then
          mkEvaluationLib base null
        else
          throw ''
            caisson.home-manager: this evaluation names
              ${named}
            as its home-manager, and the composed library carries `lib.hm`
            from the home-manager this composition declares,
              ${declaredSrc}.
            A home-manager evaluation runs on one library, so the two must be
            the same tree. Declare the other tree as
            `defaultEcosystemSrc.home-manager` in a mkLib call and evaluate
            under the library that composes, or drop the `ecosystemSrc`
            argument.
          '';

      # Provenance derives from what composes: the ecosystem source
      # handed to the entry point and the nixpkgs the package set was
      # instantiated from. `root` is the tree that builds the home, as
      # the composition records it (`lib.caisson-core.libManifest.root`);
      # its out path is recorded as `selfOutPath`, the field of schema 3.
      mkSourceMeta =
        {
          profileName,
          hostName ? null,
          hostKind ? "standalone",
          schemaVersion ? 3,
          root ? null,
          nixpkgsOutPath ? null,
          homeManagerOutPath ? null,
          baseSystem ? null,
        }:
        let
          canonical = {
            inherit
              hostKind
              hostName
              profileName
              schemaVersion
              ;
            selfOutPath = resolveOutPath root;
            inherit nixpkgsOutPath homeManagerOutPath;
            # The out path of the host's NixOS system *without* home-manager:
            # the coherence check compares this string, so it must not carry
            # derivation context; stripping it keeps embedding from forcing
            # a build.
            baseSystemOutPath =
              if baseSystem == null then
                null
              else
                builtins.unsafeDiscardStringContext (resolveOutPath baseSystem);
          };
        in
        canonical
        // {
          fingerprint = builtins.hashString "sha256" (builtins.toJSON canonical);
        };

      mkSourceMetaModule =
        sourceMeta:
        mkModule (
          { ... }:
          {
            config,
            lib,
            pkgs,
            ...
          }:
          {
            _file = "caisson-home-manager/sourceMetaModule";
            options.caisson-home-manager = {
              # No `default`: the module system counts an option default as a
              # definition in the readOnly check (lib/modules.nix
              # evalOptionValue prepends it to defs'), so readOnly + default
              # throws "set multiple times" the moment anything reads the
              # option.  This module always defines the value anyway.
              sourceMeta = lib.mkOption {
                type = lib.types.attrs;
                readOnly = true;
              };

              driftWarning = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Warn during activation if host source metadata diverges from this configuration.";
              };
            };

            config = {
              caisson-home-manager.sourceMeta = sourceMeta;

              home.activation.checkSourceCoherence = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
                _marker="/etc/caisson-home-manager/source.json"
                _expected_base="${
                  if (sourceMeta.baseSystemOutPath or null) != null then sourceMeta.baseSystemOutPath else ""
                }"
                if ${
                  if config.caisson-home-manager.driftWarning then "true" else "false"
                } && [ -n "$_expected_base" ]; then
                  if [ ! -f "$_marker" ]; then
                    echo "WARNING: no source marker at $_marker." >&2
                    echo "  This profile expects the NixOS generation to manage home-manager, but the" >&2
                    echo "  active system was built without the caisson-home-manager adapter (or has" >&2
                    echo "  never been rebuilt since it was enabled).  Run nixos-rebuild to converge." >&2
                  else
                    _host_base="$(${lib.getExe' pkgs.jq "jq"} -r '.baseSystemOutPath // empty' < "$_marker")"
                    if [ -z "$_host_base" ]; then
                      echo "WARNING: $_marker has no baseSystemOutPath." >&2
                      echo "  The active NixOS generation predates the base-system coherence scheme." >&2
                      echo "  Run nixos-rebuild to refresh it." >&2
                    elif [ "$_host_base" != "$_expected_base" ]; then
                      echo "WARNING: source drift detected." >&2
                      echo "  active system's base (non-home-manager) closure:" >&2
                      echo "    $_host_base" >&2
                      echo "  this configuration expects:" >&2
                      echo "    $_expected_base" >&2
                      echo "  The system differs from source in non-home-manager ways; run nixos-rebuild" >&2
                      echo "  to converge, or set caisson-home-manager.driftWarning = false." >&2
                    fi
                  fi
                fi
              '';
            };
          }
        );

      # The composition of the class, shared by every evaluator over
      # it: the definition of the module list, the package set and the
      # special arguments, so the evaluators cannot express different
      # profiles from the same arguments. `minimal` selects
      # home-manager's module list, and belongs to the entry point
      # rather than to the caller: the full list is
      # `lib.caisson.home-manager`, the necessary modules alone are
      # `lib.caisson.home-manager-minimal`.
      #
      # It is a function of the view being evaluated: `lib`, the
      # library of that view, and `manifest`, the manifest of the
      # evaluation. A home has an evaluation for every system in force
      # where it is declared, so the manifest is that of an evaluation
      # at a system: the name, the system and the package sets come
      # from it.
      mkCommonArgs =
        {
          context,
          minimal,
        }:
        { lib, manifest }:
        args:
        let
          integrations = lib.caisson.integrations;

          # The name of the configuration this is an evaluation of.
          name = manifest.name or null;

          # The system of this evaluation.
          inherit (manifest) system;

          what = if name != null then "the home `${name}` at ${system}" else "this home at ${system}";

          # The package sets available to the home, each at the system
          # of the evaluation, by package config name.
          pkgSets = integrations.pkgSetsAt { inherit context what; } manifest system;

          # The set the home runs on: the selection in force at its
          # manifest, applied to those.
          pkgs = integrations.pkgSetOf { inherit context what; } manifest pkgSets;

          classRegistry = lib.caisson-core.modules.homeManager or { };
          # The framework module of the class, forced.
          frameworkModules = integrations.frameworkModules "homeManager" classRegistry;
          moduleImports = integrations.moduleImportsOf "homeManager" { inherit lib manifest; } args;

          # The configuration's module: the module passed, else the
          # configuration registered under the home's name
          # (`configs/homeManager/<name>`), else none.
          registered = lib.caisson-core.configs.homeManager or { };
          configModule =
            if (args.configModule or null) != null then
              args.configModule
            else if name != null then
              registered.${name} or null
            else
              null;

          # The user of a home is the name it is declared under,
          # unless a module of the home names another. A top is
          # declared under no name: the name it holds is the name of
          # the composition.
          declaredUnderAName = name != null && (manifest.parent.parent.type or "lib") != "lib";
          usernameModule = {
            _file = "caisson-home-manager:username";
            home.username = lib.mkDefault name;
          };

          hmSource = resolveOutPath (resolveSrc (args.ecosystemSrc or null));
          resolvedSourceMeta =
            if (args.sourceMeta or null) != null then
              args.sourceMeta
            else
              mkSourceMeta {
                profileName = "default";
                homeManagerOutPath = hmSource;
                nixpkgsOutPath = resolveOutPath (pkgs.path or null);
              };
        in
        {
          inherit minimal pkgs;
          check = if (args.check or null) == null then true else args.check;
          sourceMeta = resolvedSourceMeta;
          configuration = {
            imports =
              frameworkModules
              ++ moduleImports classRegistry
              ++ (if configModule == null then [ ] else [ configModule ])
              ++ [
                (mkSourceMetaModule resolvedSourceMeta)
                { programs.home-manager.path = final.mkDefault hmSource; }
              ]
              ++ (if declaredUnderAName then [ usernameModule ] else [ ]);
          };
          # The library of the view, with the module system tied over
          # it, is what the evaluation runs on, and it carries
          # `lib.hm`, so the modules see one library with the
          # home-manager namespace under the name home-manager reads.
          lib = libFor lib (args.ecosystemSrc or null);
          # Framework defaults first; the values the caller passed win on
          # conflict. home-manager names these extraSpecialArgs; the
          # caisson name is specialArgs.
          extraSpecialArgs = {
            # The package sets at the system of the home, by config
            # name.
            inherit pkgSets;
            osConfig = args.osConfig or null;
            sourceMeta = resolvedSourceMeta;
          }
          // (if (args.specialArgs or null) != null then args.specialArgs else { });
          # The module tree the evaluation reads: home-manager's
          # module list, its module files and the `modulesPath` special
          # argument its news entries interpolate.
          modulesPath = "${hmSource}/modules";
        };

      # The evaluator's call, from the composition above: everything
      # the evaluation takes (configuration, pkgs, lib, modulesPath,
      # minimal, check, extraSpecialArgs) can be set or replaced
      # through the twin's `ecosystemArgs`. An integration that
      # evaluates the class the other way reads this through
      # `lib.caisson.home-manager.compose`.
      compose =
        {
          context ? "lib.caisson.home-manager.mkConfiguration",
          # Whether the evaluation imports home-manager's necessary
          # modules alone instead of its whole module tree.
          minimal ? false,
        }:
        view: args:
        let
          common = mkCommonArgs { inherit context minimal; } view args;
        in
        common
        // {
          ecosystemArgs = {
            inherit (common)
              check
              configuration
              extraSpecialArgs
              lib
              minimal
              modulesPath
              pkgs
              ;
          };
        };

      # The evaluation, from the composed library. `modules/default.nix`
      # of the home-manager source is the standalone entry point, and
      # its lib-construction step, `import ./lib/stdlib-extended.nix
      # lib`, rebuilds nixpkgs' fixpoint through `extend` and drops
      # every attribute the composition contributed: the modules would
      # run on a library reassembled inside the evaluator. Everything
      # else that entry point does is reproduced here line for line
      # against the same source tree, with the composed library
      # standing where it built a library.
      #
      # The module list, the module files, the class name and
      # `modulesPath` all come from the tree `modulesPath` names, so
      # home-manager decides what is evaluated. Beside the library
      # the evaluation runs on, it differs from the upstream entry
      # point in the package set: `useNixpkgsModule` is false, so
      # `pkgs` is the set the home is given, as it is where
      # home-manager's NixOS module sets `useGlobalPkgs`. With
      # home-manager's nixpkgs module, `pkgs` would be nixpkgs
      # imported again from the path of that set under the
      # `nixpkgs.config` and `nixpkgs.overlays` of the home, and the
      # config and the overlays of the package config would be left
      # out.
      evaluate =
        _composed:
        {
          configuration,
          pkgs,
          lib,
          modulesPath,
          minimal ? false,
          check ? true,
          useNixpkgsModule ? false,
          extraSpecialArgs ? { },
        }:
        let
          collectFailed = cfg: map (x: x.message) (lib.filter (x: !x.assertion) cfg.assertions);

          showWarnings =
            res:
            let
              f = w: x: builtins.trace "\x1b[1;31mwarning: ${w}\x1b[0m" x;
            in
            lib.foldr f res res.config.warnings;

          hmModules = import "${modulesPath}/modules.nix" {
            inherit
              check
              pkgs
              minimal
              lib
              useNixpkgsModule
              ;
          };

          rawModule = lib.evalModules {
            modules = [ configuration ] ++ hmModules;
            class = "homeManager";
            specialArgs = {
              inherit modulesPath;
              # The `lib` argument every module receives.
              # `evalModules` builds that argument from the `lib` its
              # `lib/modules.nix` closed over, which is the
              # fixpoint the `nixpkgs-lib` entry read rather than
              # what this composition built, and `// specialArgs` in
              # that file is where a caller says otherwise. Naming it
              # here is what puts the composed library, `lib.hm` among
              # its attributes, in front of the modules.
              inherit lib;
            }
            // extraSpecialArgs;
          };

          moduleChecks =
            raw:
            showWarnings (
              let
                failed = collectFailed raw.config;
                failedStr = lib.concatStringsSep "\n" (map (x: "- ${x}") failed);
              in
              if failed == [ ] then
                raw
              else
                throw ''

                  Failed assertions:
                  ${failedStr}''
            );

          withExtraAttrs =
            rawModule':
            let
              module = moduleChecks rawModule';
            in
            module
            // {
              inherit (module.config.home) activationPackage;

              # home-manager keeps this name beside activationPackage
              # for the configurations that read it.
              activation-script = module.config.home.activationPackage;

              newsDisplay = rawModule'.config.news.display;
              newsEntries = lib.sort (a: b: a.time > b.time) (
                lib.filter (a: a.condition) rawModule'.config.news.entries
              );

              inherit (module._module.args) pkgs;

              extendModules = args: withExtraAttrs (rawModule'.extendModules args);
            };
        in
        withExtraAttrs rawModule;

      mkConfiguration = final.caisson.home-manager.mkConfiguration;

      # The evaluator step of a home, on the view being evaluated: the
      # evaluation over the composition, with the twin's
      # `ecosystemArgs` merged over the composed call last. `variant`
      # is what `compose` takes, the entry point and its module list.
      # An integration that evaluates the class the other way builds
      # its configurations from this.
      evaluation =
        variant: args: view:
        let
          composed = compose variant view args;
          value = evaluate composed (
            composed.ecosystemArgs // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { })
          );
        in
        {
          inherit value;
          # What `home-manager switch` builds and runs.
          outputs = {
            inherit (value) activationPackage;
          };
        };

      # A home is published as `homeConfigurations.<name>`, the
      # evaluated home, which is what the home-manager CLI reads. A
      # home beneath a NixOS configuration is named `<user>@<host>`,
      # the name it is passed up under and the name that NixOS
      # configuration is declared under, which is where the CLI looks
      # (`$USER@$(hostname)`); a home with no NixOS configuration above
      # it keeps its name.
      exportsTo = {
        attrset = "homeConfigurations";
        value = manifest: manifest.value;
        name =
          { name, manifest }:
          let
            host = (manifest.nearest.nixos or { }).name or null;
          in
          if host == null then
            { value = name; }
          else
            {
              value = "${name}@${host}";
              description = "named ${name}@${host} from its name and the name of the NixOS configuration it is under";
            };
      };

      configuration =
        variant: args:
        selection.mkModuleConfiguration {
          type = "home-manager";
          # A home is evaluated at a system: it has an evaluation for
          # every system in force where it is declared.
          perSystem = true;
          defaultPkgs = args.defaultPkgs or null;
          inherit exportsTo;
          evaluate = evaluation variant args;
        };

      # A home that is a top, as the home-manager CLI reads it: the
      # evaluated home, with its `activationPackage`. Where the
      # composition has several systems in force, it is the evaluated
      # homes by system, and where it has none, the empty set
      # (`integrations.topValue`).
      mkTopConfiguration =
        rawArgs:
        selection.topValue (
          final.caisson-core.finalizeTop (final.caisson.home-manager.mkConfiguration rawArgs)
        );

      mkStandaloneAdapter =
        args@{
          moduleImports ? selection.defaultModuleImports,
          extraModuleImports ? (_registry: [ ]),
          ...
        }:
        let
          selectedModules = moduleImports registry ++ extraModuleImports registry;
        in
        {
          homeModules = coreModules ++ selectedModules;
          # A home over the adapter's arguments, as `mkConfiguration`
          # returns it: a configuration, declared under
          # `caisson.home-manager.configurations` or finalized as a
          # top.
          buildHome = configModule: mkConfiguration (args // { inherit configModule moduleImports; });
        };

      # The adapter's signature is open, its extras being NixOS-module
      # options rather than evaluator arguments; home-manager's
      # `extraSpecialArgs` spelling is refused with a pointer to
      # `specialArgs`.
      mkNixosAdapter =
        rawArgs:
        if rawArgs ? extraSpecialArgs then
          throw "lib.caisson.home-manager.mkNixosAdapter does not accept `extraSpecialArgs`: pass extra module arguments as `specialArgs`."
        else if rawArgs ? pkgSets then
          throw "lib.caisson.home-manager.mkNixosAdapter does not accept `pkgSets`: the homes run on the package set in force where the NixOS configuration is declared, and `defaultPkgs` selects another."
        else
          mkNixosAdapterChecked rawArgs;
      mkNixosAdapterChecked =
        {
          users,
          ecosystemSrc ? null,
          hostName ? null,
          hostKind ? "nixos",
          # The same host's NixOS system evaluated *without* this adapter
          # module.  Its out path is what standalone home-manager activations
          # compare against to detect non-home-manager drift; without it the
          # marker cannot vouch for coherence.
          baseSystem ? null,
          sourceMeta ? null,
          # The package set the homes run on, as the `defaultPkgs` of
          # `mkConfiguration` selects it; the set in force at the
          # NixOS configuration when absent. It applies to the
          # "user-service" mode, where each home is a configuration.
          defaultPkgs ? null,
          moduleImports ? selection.defaultModuleImports,
          extraModuleImports ? (_registry: [ ]),
          sharedModules ? [ ],
          useGlobalPkgs ? true,
          useUserPackages ? true,
          # How the NixOS generation triggers home-manager activation:
          #
          # "upstream": home-manager's nixos module delivery (system
          # units at boot).  Fine when the OS declares the users and their
          # homes are available at boot.
          #
          # "user-service": a complete user unit in /etc, gated by
          # ConditionUser, that runs `activate` when the user's service
          # manager starts.  It leaves `users.users` untouched, so it is safe for
          # systemd-homed hosts, where a NixOS-created passwd entry would
          # conflict with the homed user record and the home directory is
          # only mounted at login anyway.  Limited to one user: a
          # shared unit cannot carry per-user ExecStarts.
          activationMode ? "upstream",
          specialArgs ? { },
          ...
        }:
        assert final.assertMsg (builtins.elem activationMode [
          "upstream"
          "user-service"
        ]) "mkNixosAdapter: activationMode must be \"upstream\" or \"user-service\".";
        assert final.assertMsg (
          activationMode != "user-service" || builtins.length (builtins.attrNames users) == 1
        ) "mkNixosAdapter: activationMode \"user-service\" supports exactly one user.";
        mkNixosModule (
          { ... }:
          {
            config,
            lib,
            pkgs,
            ...
          }:
          let
            # The manifest of the NixOS evaluation this module is in,
            # where caisson performs that evaluation; null in a NixOS
            # evaluation made another way, a test node for one.
            nixosManifest = lib.caisson-core.evalManifest or null;
            system = pkgs.stdenv.hostPlatform.system;
            # The package sets at the system of the machine, by config
            # name, as its modules receive them.
            pkgSetsHere =
              if nixosManifest == null then
                { default = pkgs; }
              else
                selection.pkgSetsAt {
                  context = "lib.caisson.home-manager.mkNixosAdapter";
                  what = "the NixOS configuration at ${system}";
                } nixosManifest system;
            sharedClassModules = coreModules ++ moduleImports registry ++ extraModuleImports registry;
            hmSource = resolveOutPath (resolveSrc ecosystemSrc);
            resolvedSourceMeta =
              if sourceMeta != null then
                sourceMeta
              else
                mkSourceMeta {
                  profileName = "hosted";
                  inherit
                    baseSystem
                    hostKind
                    hostName
                    ;
                  homeManagerOutPath = hmSource;
                  nixpkgsOutPath = resolveOutPath (pkgs.path or null);
                };
            sourceMetaModule = mkSourceMetaModule resolvedSourceMeta;

            mkUserConfig =
              _username: userArgs:
              let
                userModuleImports = userArgs.moduleImports or (_modules: [ ]);
                userClassModules = userModuleImports registry;
                configModule =
                  if userArgs ? configModule then
                    userArgs.configModule
                  else
                    throw "mkNixosAdapter requires `users.<name>.configModule`.";
              in
              {
                imports = userClassModules ++ [ configModule ];
              };
          in
          if activationMode == "user-service" then
            # No home-manager NixOS module at all: it cannot evaluate without
            # a `users.users.<name>` entry (its injected defs dereference the
            # user record), and creating the entry would conflict with
            # systemd-homed's ownership of the account.  Instead each user is
            # a home as `mkConfiguration` builds it, the configuration
            # `home-manager switch` evaluates (the embedded generation is the
            # standalone generation by construction), and a complete /etc
            # user unit runs its activation when the user's service manager
            # starts.
            #
            # Each home is finalized here, under the user's name:
            # beneath the NixOS evaluation where caisson performs it,
            # so the home runs at the system of the machine and on the
            # package set in force there, and beneath the composition
            # otherwise, read at the system of the machine.
            (
              let
                username = builtins.head (builtins.attrNames users);
                homesParent = if nixosManifest == null then final.caisson-core.libManifest else nixosManifest;
                userActivations = builtins.mapAttrs (
                  username: userArgs:
                  let
                    evaluations =
                      final.caisson-core.finalizeChild
                        {
                          name = username;
                          parent = homesParent;
                          what = "the home of `${username}`";
                        }
                        (mkConfiguration {
                          inherit ecosystemSrc specialArgs defaultPkgs;
                          configModule =
                            if userArgs ? configModule then
                              userArgs.configModule
                            else
                              throw "mkNixosAdapter requires `users.<name>.configModule`.";
                          moduleImports = userArgs.moduleImports or moduleImports;
                          sourceMeta = userArgs.sourceMeta or resolvedSourceMeta;
                        });
                  in
                  (evaluations.${system} or (throw ''
                    lib.caisson.home-manager.mkNixosAdapter: the home of `${username}` has
                    no evaluation at ${system}, the system of this machine. The systems
                    in force for it are ${
                      if evaluations == { } then
                        "none"
                      else
                        builtins.concatStringsSep ", " (builtins.attrNames evaluations)
                    }.
                  '')
                  ).value.activationPackage
                ) users;
              in
              {
                options.caisson-home-manager.hostedActivations = lib.mkOption {
                  type = lib.types.attrsOf lib.types.package;
                  readOnly = true;
                  description = ''
                    Per-user home-manager activation packages embedded in this
                    NixOS generation (activationMode = "user-service").
                  '';
                };

                config = {
                  caisson-home-manager.hostedActivations = userActivations;

                  systemd.user.services.home-manager = {
                    description = "Home Manager activation for ${username}";
                    unitConfig = {
                      ConditionUser = username;
                      RequiresMountsFor = "%h";
                    };
                    environment = {
                      # Mirrors upstream's base unit: Qt tools invoked during
                      # activation must not require a display.
                      QT_QPA_PLATFORM = "offscreen";
                    };
                    serviceConfig = {
                      Type = "oneshot";
                      RemainAfterExit = true;
                      TimeoutStartSec = "5m";
                      SyslogIdentifier = "hm-activate-${username}";
                      # A login shell, as upstream's system units use: the
                      # standalone activation script expects the user's normal
                      # environment (nix on PATH to update its profile).
                      ExecStart = pkgs.writeScript "hm-user-activate-${username}" ''
                        #! ${pkgs.runtimeShell} -el
                        exec ${userActivations.${username}}/activate
                      '';
                    };
                    wantedBy = [ "default.target" ];
                  };

                  environment.etc."caisson-home-manager/source.json".text = builtins.toJSON resolvedSourceMeta;
                };
              }
            )
          else
            {
              imports = [ "${hmSource}/nixos" ];

              "home-manager" = {
                inherit
                  useGlobalPkgs
                  useUserPackages
                  ;
                # Framework defaults first; the values the caller passed
                # win on conflict. The library of an embedded user
                # generation is the library of the NixOS evaluation
                # around it, which home-manager's NixOS module extends
                # with its `hm` namespace and installs as the
                # submodule's `lib` special argument
                # (nixos/common.nix). `extraSpecialArgs` merges over
                # that installation, so a `lib` here would replace the
                # extended library and take `lib.hm` with it; the
                # library reaches this path through the NixOS
                # evaluation instead. That extension is the same
                # rebuild of nixpkgs' fixpoint the standalone path
                # composes `lib.hm` to avoid, and it is the nixos
                # integration that delivers the composed library to a
                # NixOS evaluation.
                extraSpecialArgs = {
                  pkgSets = pkgSetsHere;
                  sourceMeta = resolvedSourceMeta;
                }
                // specialArgs;
                # The extra entries match the standalone defaults of
                # mkCommonArgs, so a user generation inside the NixOS
                # configuration evaluates to the same derivation as the
                # standalone profile built from the same source.
                sharedModules =
                  sharedModules
                  ++ sharedClassModules
                  ++ [
                    sourceMetaModule
                    { programs.home-manager.path = final.mkDefault hmSource; }
                    (
                      {
                        config,
                        lib,
                        pkgs,
                        ...
                      }:
                      {
                        config = lib.mkMerge [
                          # Hosted default is the OS's i18n.glibcLocales;
                          # standalone default is pkgs.glibcLocales.
                          { i18n.glibcLocales = lib.mkDefault pkgs.glibcLocales; }
                          # Upstream skips the home-manager CLI for submodule
                          # evaluations, but the standalone CLI must
                          # survive a nixos-rebuild "revert" or the user cannot
                          # layer standalone switches afterwards.
                          (lib.mkIf (config.programs.home-manager.enable && config.submoduleSupport.enable) {
                            home.packages = [ config.programs.home-manager.package ];
                          })
                        ];
                      }
                    )
                  ];
                users = lib.mapAttrs mkUserConfig users;
              };

              environment.etc."caisson-home-manager/source.json".text = builtins.toJSON resolvedSourceMeta;
            }
        );

      assertSourceCoherence =
        {
          hostSourceMeta,
          targetSourceMeta,
          allowDrift ? false,
        }:
        let
          hostFp = hostSourceMeta.fingerprint or null;
          targetFp = targetSourceMeta.fingerprint or null;
        in
        if allowDrift then
          true
        else if hostFp == null || targetFp == null then
          throw "Source coherence check failed: fingerprint missing from host or target metadata."
        else if hostFp == targetFp then
          true
        else
          throw ''
            Source coherence check failed.
            host fingerprint: ${hostFp}
            target fingerprint: ${targetFp}
          '';
      integration = selection.mkIntegration {
        name = "home-manager";
        class = "homeManager";
        # What these return is a configuration, a function of
        # `{ name, parent }`: a parent that declares it under
        # `caisson.home-manager.configurations.<name>` finalizes it,
        # and `mkTopConfiguration` finalizes it at a top.
        # `lib.caisson.home-manager-minimal` takes the same arguments.
        # The home is evaluated at every system in force where it is
        # declared, and its package sets come from the composition,
        # through the manifest; `defaultPkgs` selects the set it runs
        # on.
        mkConfiguration =
          {
            # The home's module. When absent, the configuration
            # registered under the home's name
            # (`lib.caisson-core.configs.homeManager.<name>`), if any.
            # Further modules of the class are selected with
            # `moduleImports`, from the registry. home-manager's module
            # list belongs to the entry point: mkConfiguration
            # evaluates with the whole module tree,
            # lib.caisson.home-manager-minimal.mkConfiguration with the
            # necessary modules alone.
            configModule ? null,
            # The home-manager source tree; resolved from the
            # composition's declarations when absent.
            ecosystemSrc ? null,
            # The package set the home runs on: a function that
            # receives the package sets available where it is
            # declared, as an attribute set by package config name,
            # each at the system of the evaluation, and returns the
            # set to run on. When absent, the selection of the nearest
            # configuration above, which beneath a NixOS configuration
            # is the set of that configuration, and the set named
            # `default` where none above selects.
            defaultPkgs ? null,
            # The selection over the homeManager class of the registry.
            # It replaces the default of the class, which is every
            # entry named `default` followed by what the configurations
            # above added.
            moduleImports ? null,
            # A selection added to that selection, whichever it is.
            extraModuleImports ? null,
            # Extra module arguments, merged over those the framework
            # supplies; home-manager names these `extraSpecialArgs`.
            specialArgs ? null,
            # The NixOS configuration around this configuration, the
            # `osConfig` module argument.
            osConfig ? null,
            # home-manager's `check`.
            check ? null,
            # The source metadata the activation coherence check
            # compares; derived from the sources when absent.
            sourceMeta ? null,
          }@args:
          configuration { } args;
        # The same arguments and `ecosystemArgs`, the evaluator's
        # arguments merged over the composed call last.
        mkConfigurationWithEcosystemArgs =
          {
            configModule ? null,
            ecosystemSrc ? null,
            defaultPkgs ? null,
            moduleImports ? null,
            extraModuleImports ? null,
            specialArgs ? null,
            osConfig ? null,
            check ? null,
            sourceMeta ? null,
            ecosystemArgs ? null,
          }@args:
          configuration { } args;
        extra = {
          inherit
            assertSourceCoherence
            mkNixosAdapter
            mkSourceMeta
            mkStandaloneAdapter
            mkTopConfiguration
            ;
          # What an alt over this class builds on: the composition,
          # the evaluator's call, and the two put together as a
          # configuration of this integration (`configuration`, given
          # what `compose` takes and the arguments of the entry
          # point). Both module lists come out of the same
          # home-manager source and run through the same evaluation,
          # so the entry points differ in the module list alone.
          inherit compose evaluate configuration;
        };
      };
    in
    contributeClasses prev integration.classes
    // {
      caisson = (prev.caisson or { }) // {
        home-manager = integration.namespace;
      };

      # home-manager's library under the name home-manager's modules
      # read, from the composition's declared home-manager; forced
      # only when read. This entry is where `lib.hm` comes from, so a
      # home-manager evaluation runs on one composed library that
      # already carries it.
      hm = (prev.hm or { }) // hmLibDeclared;

      # The home-manager maintainers merged into the nixpkgs
      # maintainer list, which is what the `meta.maintainers` type
      # check of nixpkgs reads (modules/lib/stdlib-extended.nix of the
      # home-manager source does the same). nixpkgs reads its list
      # from a file beside the `lib` directory, so this name forces
      # that file, and a composition whose `nixpkgs-lib` part is the
      # lib directory alone (the nixpkgs.lib mirror) has no list to
      # read: forced only when a reader asks for the merged list. A
      # composition that declares no home-manager has no maintainers
      # to merge and leaves the list as it found it.
      maintainers =
        (prev.maintainers or { }) // (if declaredSrc != null then hmLibDeclared.maintainers else { });
    };

}
