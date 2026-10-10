# SPDX-License-Identifier: MIT
#
# The home-manager integration: it owns the `homeManager` class,
# contributes the declared home-manager's library to the composition
# as `lib.hm`, and evaluates the class over the composed library with
# home-manager's module list. A home is a configuration: it is
# evaluated at every system in force where it is declared, on the
# package set in force there, and a top publishes it under
# `homeConfigurations`.
#
# A home can be declared inside a NixOS configuration. The modules
# that serve such a home are registered modules of caisson: the NixOS
# modules `home-manager-activation` and `home-manager-source-marker`,
# and the home-manager modules `nixos-parent` and
# `nixos-source-marker`.
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
      selection = final.caisson.integrations;

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

          # The NixOS configuration the home is declared inside, when
          # there is one. It is the nearest NixOS configuration above
          # the home, so a structural configuration between the two
          # changes nothing. The manifest holds the childless
          # evaluation of that NixOS configuration, which is the
          # evaluation that leaves out the configurations declared
          # inside it. The home is one of those, so the full
          # evaluation would depend on the home.
          machine = manifest.nearest.nixos or null;

          # home-manager hands a home the configuration of its machine
          # as the module argument `osConfig`, and null when the home
          # has no machine. An `osConfig` passed to the constructor
          # takes the place of the configuration of the machine.
          osConfig =
            if (args.osConfig or null) != null then
              args.osConfig
            else if machine != null then
              machine.value.config
            else
              null;

          hmSource = resolveOutPath (resolveSrc (args.ecosystemSrc or null));
        in
        {
          inherit minimal pkgs;
          check = if (args.check or null) == null then true else args.check;
          configuration = {
            imports =
              frameworkModules
              ++ moduleImports classRegistry
              ++ (if configModule == null then [ ] else [ configModule ])
              ++ [
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
            inherit pkgSets osConfig;
          }
          # home-manager also hands a home inside a machine the class
          # of the machine, as `osClass`. A home with no machine gets
          # no such argument from home-manager, so none is added here.
          #
          # home-manager's legacy argument `nixosConfig` is left at
          # null, the value home-manager gives it in a home with no
          # machine. home-manager's fontconfig module reads
          # `nixosConfig.home-manager`, an option that only
          # home-manager's NixOS module declares, and caisson does not
          # use that module.
          // (if machine != null then { osClass = "nixos"; } else { })
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
            # The value of the module argument `osConfig`. When absent,
            # a home declared inside a NixOS configuration gets the
            # configuration of that NixOS configuration, and any other
            # home gets null.
            osConfig ? null,
            # home-manager's `check`.
            check ? null,
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
            ecosystemArgs ? null,
          }@args:
          configuration { } args;
        extra = {
          inherit mkTopConfiguration;
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
