# SPDX-License-Identifier: MIT
#
# The home-manager integration: it owns the `homeManager` class,
# contributes the declared home-manager's library to the composition
# as `lib.hm`, and evaluates the class over the composed library with
# home-manager's module list. A home-manager configuration is
# evaluated per system, once for each system its parent evaluates its
# children for, on the package set selected there, and a caisson top publishes it
# under `homeConfigurations`.
#
# A home-manager configuration can be declared inside a NixOS
# configuration. The modules for such a home-manager
# configuration are registered modules of caisson: the NixOS
# modules `home-manager-activation` and `home-manager-source-marker`,
# and the home-manager modules `nixos-parent` and
# `nixos-source-marker`.
{
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

      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc ecosystem;
      ecosystemAccountOf = final.caisson.integrations.ecosystemAccountOf ecosystem;
      ecosystem = {
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
      # message: a composition may leave the home-manager source to the
      # `ecosystemSrc` of each home-manager configuration.
      declaredSrc =
        let
          manifest = final.caisson-core.libManifest or { };
        in
        resolveOutPath (
          final.caisson-core.resolve {
            name = "home-manager";
            defaults = manifest.defaultEcosystemSrc or { };
            dependencies = manifest.dependencies or { };
          }
        );

      # home-manager's library over a library: `modules/lib/default.nix`
      # of the source tree at `src` applied to `lib`. Its functions call each
      # other through `lib.hm`, so the library they are applied to
      # carries the result as `hm`, and every nixpkgs name they read
      # is a name that library has.
      mkHmLib = src: lib: import "${src}/modules/lib" { inherit lib; };

      # The declared home-manager's library over the composed library,
      # the `hm` entry this integration contributes; forced only when
      # read. Reading it in a composition that declares no
      # home-manager names the places a home-manager source comes from.
      hmLibDeclared =
        if declaredSrc != null then
          mkHmLib declaredSrc final
        else
          throw ''
            lib.hm: this composition declares no home-manager. Declare it as
            `defaultEcosystemSrc.home-manager` in the mkLib call, or pin a
            source named `home-manager` in the `dependencies` passed to mkLib; a configuration
            that names its home-manager through `ecosystemSrc` runs on the
            composed library carrying `hm` from that source.
          '';

      # The library a home-manager configuration runs on: the composed library with
      # the module system tied over it. The module system hands `lib`
      # to every module it evaluates, those of the main evaluation
      # through `specialArgs` and the rest, submodules and the
      # evaluations the home-manager source runs beside the main evaluation
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
      # `base` is the library the configuration is evaluated with, the
      # composed library carrying the manifest of the configuration.
      #
      # `hmSrc` names the source `hm` comes from when the composition
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
      # and its `lib.hm` come from the same home-manager source. With a declared
      # home-manager, the composed library carries `hm` from that source
      # as an entry, and a configuration whose `ecosystemSrc` names a
      # different source is refused, the message naming the declaration
      # that composes an `hm` for it. With none declared, the source the
      # configuration names supplies both.
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
            caisson.home-manager: this home-manager configuration names
              ${named}
            as its home-manager, and the composed library holds `lib.hm`
            from the home-manager this composition declares,
              ${declaredSrc}.
            A home-manager evaluation runs on one library, so the two must be
            the same source. Declare the other source as
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
      # It is a function of what the configuration is evaluated with:
      # `lib`, the library, and `manifest`, the manifest of the
      # configuration. A home-manager configuration has an evaluation
      # result for each system its parent evaluates its children for,
      # so the manifest is that of the evaluation for one system: the
      # name, the system and the package sets come from it.
      mkCommonArgs =
        {
          context,
          minimal,
        }:
        { lib, manifest }:
        args:
        let
          integrations = lib.caisson.integrations;

          # The name of the configuration being evaluated.
          name = manifest.name or null;

          # The system the configuration is evaluated for.
          inherit (manifest) system;

          what =
            if name != null then
              "the home-manager configuration `${name}` for ${system}"
            else
              "this home-manager configuration for ${system}";

          # The package sets available to the home-manager
          # configuration, each for the system it is evaluated for, by
          # package config name.
          pkgSets = integrations.pkgSetsForSystem { inherit context what; } manifest system;

          # The set the home-manager configuration runs on: the package
          # set selection that applies to its manifest, applied to those.
          pkgs = integrations.pkgSetOf { inherit context what; } manifest pkgSets;

          classRegistry = lib.caisson.modules.homeManager or { };
          # The framework module of the class, forced.
          frameworkModules = integrations.frameworkModules "homeManager" classRegistry;
          moduleImports = integrations.moduleImportsOf "homeManager" { inherit lib manifest; } args;

          # The configuration's module: the module passed, else the
          # configuration registered under the name of the home-manager
          # configuration (`configs/homeManager/<name>`), else none.
          configModule = integrations.configModuleOf {
            inherit lib name;
            class = "homeManager";
            configModule = args.configModule or null;
          };

          # The user of a home-manager configuration is the name it is
          # declared under, unless a module of the home-manager
          # configuration names another. A caisson top is
          # declared under no name: the name it holds is the name of
          # the composition.
          declaredUnderAName = name != null && (manifest.parent.parent.type or "lib") != "lib";
          usernameModule = integrations.caissonModule {
            key = "caisson.homeManager.username";
            file = "caisson-home-manager:username";
            module = {
              _file = "caisson-home-manager:username";
              home.username = lib.mkDefault name;
            };
          };

          # The home-manager command of the home-manager configuration:
          # the home-manager source it was evaluated with.
          pathModule = integrations.caissonModule {
            key = "caisson.homeManager.path";
            file = "caisson-home-manager:path";
            module = {
              programs.home-manager.path = final.mkDefault hmSource;
            };
          };

          # The system configuration the home-manager configuration is
          # declared inside, when there is one: the nearest NixOS,
          # nix-darwin or system-manager configuration above the
          # home-manager configuration, so a structural configuration
          # between the two changes nothing. The manifest holds the
          # result of the childless evaluation of that configuration,
          # which leaves out the configurations declared inside it. The
          # home-manager configuration is one of those, so the result of
          # the full evaluation would depend on the home-manager
          # configuration.
          systemConfiguration = selection.nearestOf systemConfigurationTypes manifest;

          # home-manager hands a home-manager configuration the
          # evaluated options of that system configuration as the
          # module argument `osConfig`, and null when the home-manager
          # configuration is declared inside none. An `osConfig` passed
          # to the constructor takes the place of those options.
          osConfig =
            if (args.osConfig or null) != null then
              args.osConfig
            else if systemConfiguration != null then
              systemConfiguration.value.config
            else
              null;

          hmSource = resolveOutPath (resolveSrc (args.ecosystemSrc or null));

          # The modules of the composition, which the configuration
          # module imports: the framework module of the class, the
          # modules selected from the registry, the configuration's
          # module, the module that names the home-manager command and,
          # for a home-manager configuration declared under a name, the
          # module that names the user.
          configurationModules =
            frameworkModules
            ++ moduleImports classRegistry
            ++ (if configModule == null then [ ] else [ configModule ])
            ++ [ pathModule ]
            ++ (if declaredUnderAName then [ usernameModule ] else [ ]);
        in
        {
          inherit minimal pkgs;
          check = if (args.check or null) == null then true else args.check;
          inherit configurationModules;
          configuration = {
            imports = configurationModules;
          };
          # The library the configuration is evaluated with, with the
          # module system tied over it, is what its modules run on, and it carries
          # `lib.hm`, so the modules see one library with the
          # home-manager namespace under the name home-manager reads.
          lib = libFor lib (args.ecosystemSrc or null);
          # Framework defaults first; the values the caller passed win on
          # conflict. home-manager names these extraSpecialArgs; the
          # caisson name is specialArgs.
          extraSpecialArgs = {
            # The package sets for the system of the home-manager
            # configuration, by config name.
            inherit pkgSets osConfig;
          }
          # home-manager also hands a home-manager configuration inside
          # a system configuration the class of that configuration, as
          # `osClass`. A home-manager configuration declared inside none
          # gets no such argument from home-manager, so none is added
          # here. home-manager's nix-darwin module also hands a
          # home-manager configuration the evaluated options of the
          # nix-darwin configuration as `darwinConfig`.
          #
          # home-manager's legacy argument `nixosConfig` is left at
          # null, the value home-manager gives it in a home-manager
          # configuration declared inside no system configuration.
          # home-manager's fontconfig module reads
          # `nixosConfig.home-manager`, an option that only
          # home-manager's NixOS module declares, and caisson does not
          # use that module.
          // (if systemConfiguration != null then { osClass = systemConfiguration.type; } else { })
          // (
            if systemConfiguration != null && systemConfiguration.type == "darwin" then
              { darwinConfig = osConfig; }
            else
              { }
          )
          // (if (args.specialArgs or null) != null then args.specialArgs else { });
          # The module tree the evaluation reads: home-manager's
          # module list, its module files and the `modulesPath` special
          # argument its news entries interpolate.
          modulesPath = "${hmSource}/modules";
        };

      # The evaluator's call, from the composition above: everything
      # the evaluation takes (configuration, pkgs, lib, modulesPath,
      # minimal, check, extraSpecialArgs) can be set or replaced
      # through the `ecosystemArgs` of the `WithEcosystemArgs` variant. An integration that
      # evaluates the class the other way reads this through
      # `lib.caisson.home-manager.compose`.
      compose =
        {
          context ? "lib.caisson.home-manager.mkConfiguration",
          # Whether the evaluation imports home-manager's necessary
          # modules alone instead of its whole module tree.
          minimal ? false,
        }:
        given: args:
        let
          common = mkCommonArgs { inherit context minimal; } given args;
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
      # `modulesPath` all come from the directory `modulesPath` names, so
      # home-manager decides what is evaluated. Beside the library
      # the evaluation runs on, it differs from the upstream entry
      # point in the package set: `useNixpkgsModule` is false, so
      # `pkgs` is the set the home-manager configuration is given, as
      # it is where home-manager's NixOS module sets `useGlobalPkgs`.
      # With home-manager's nixpkgs module, `pkgs` would be nixpkgs
      # imported again from the path of that set under the
      # `nixpkgs.config` and `nixpkgs.overlays` of the home-manager
      # configuration, and the config and the overlays of the package
      # config would be left out.
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

      # The evaluator step of a home-manager configuration, on the lib
      # and manifest it is evaluated with: the evaluation over the composition, with the
      # `ecosystemArgs` of the `WithEcosystemArgs` variant merged over the composed call last.
      # `variant` is what `compose` takes, the entry point and its
      # module list. An integration that evaluates the class the other
      # way builds
      # its configurations from this.
      evaluation =
        variant: args: given:
        let
          composed = compose variant given args;
          ecosystemArgs =
            composed.ecosystemArgs
            // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { });
          value = evaluate composed ecosystemArgs;
        in
        {
          inherit value;
          # Where home-manager came from, as `resolveSrc` resolved it.
          ecosystems.home-manager = ecosystemAccountOf {
            explicit = args.ecosystemSrc or null;
            manifest = final.caisson-core.libManifest or { };
          };
          # What evalModules received: each module the configuration
          # module imports, then home-manager's module list. A
          # configuration module given through `ecosystemArgs` is
          # recorded as a single module.
          modules =
            (
              if (args.ecosystemArgs or null) != null && args.ecosystemArgs ? configuration then
                [ ecosystemArgs.configuration ]
              else
                composed.configurationModules
            )
            ++ [
              (final.caisson.integrations.ecosystemUnit {
                key = "home-manager";
                project = "home-manager";
                file = "modules/modules.nix";
              })
            ];
          # What `home-manager switch` builds and runs.
          outputs = {
            inherit (value) activationPackage;
          };
        };

      # The integrations whose configurations are the NixOS, nix-darwin
      # and system-manager configurations a home-manager configuration
      # can be declared inside.
      systemConfigurationTypes = [
        "nixos"
        "darwin"
        "system-manager"
      ];

      # A home-manager configuration is published as
      # `homeConfigurations.<name>`, the evaluated home-manager
      # configuration, which is what the home-manager CLI reads. A
      # home-manager configuration declared inside a NixOS or nix-darwin
      # configuration is named `<user>@<configuration>`, the name it is
      # passed up under and the name that NixOS or nix-darwin
      # configuration is declared under, which is where the CLI looks
      # (`$USER@$(hostname)`); a home-manager configuration with no such
      # configuration above it keeps its name.
      exportsTo = {
        attrset = "homeConfigurations";
        value = manifest: manifest.value;
        name =
          { name, manifest }:
          let
            systemConfiguration = final.caisson.integrations.nearestOf systemConfigurationTypes manifest;
            systemConfigurationName =
              if systemConfiguration == null then null else systemConfiguration.name or null;
          in
          if systemConfigurationName == null then
            { value = name; }
          else
            {
              value = "${name}@${systemConfigurationName}";
              description = "named ${name}@${systemConfigurationName} from its name and the name of the ${
                { nixos = "NixOS"; }.${systemConfiguration.type} or systemConfiguration.type
              } configuration it is under";
            };
      };

      # The profile adapter of a home-manager configuration: where the
      # Nix profiles of the home-manager configuration are, what each
      # holds, and what sets each, as data read from the evaluated
      # home-manager configuration of `manifest`. The activation
      # module of a NixOS or nix-darwin configuration reads it to install the packages it sets,
      # and topside reads it to show the profiles.
      #
      # `activate` is the program that activates the home-manager
      # configuration, the `activate` script of its activation
      # package. Each profile has `path`, the shell text of its path,
      # `holds`, the store path it holds once the home-manager
      # configuration is applied, and `setBy`, what sets it:
      # `activation`, the `activate` script run as the user, or
      # `machine`, a switch of the NixOS or nix-darwin configuration the
      # home-manager configuration is declared inside, which builds the profile as
      # part of the system.
      #
      # `generations` is the home-manager profile, whose generations
      # `home-manager generations` lists. Each generation is an
      # activation package. home-manager puts it in
      # `$XDG_STATE_HOME/nix/profiles` when that directory exists, and
      # in `/nix/var/nix/profiles/per-user/$USER` otherwise
      # (`modules/lib-bash/activation-init.sh` of home-manager).
      # `activate` sets it when it is run with no driver version, as
      # the units of a NixOS configuration run it, and `home-manager switch` sets
      # it before it runs `activate`.
      #
      # `packages` is the profile that holds `home.path`, the packages
      # of the home-manager configuration, at `home.profileDirectory`.
      # By default `activate` installs `home.path` there with `nix-env`
      # or `nix profile`. Where home-manager's option
      # `submoduleSupport.externalPackageInstall` is true, which
      # `caisson.useUserPackages` sets, the path is
      # `/etc/profiles/per-user/<user>` and the NixOS or nix-darwin
      # configuration sets it.
      profileAdapter =
        manifest:
        let
          inherit (manifest.value.config) home;
          # A module list written for a test may leave out the file of
          # home-manager that declares `submoduleSupport`, and then the
          # activation installs the packages, as with the option false.
          externalPackageInstall =
            (manifest.value.config.submoduleSupport or { }).externalPackageInstall or false;
        in
        {
          activate = "${manifest.outputs.activationPackage}/activate";
          profiles = {
            generations = {
              path = "\${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/home-manager";
              holds = manifest.outputs.activationPackage;
              setBy = "activation";
            };
            packages = {
              path = home.profileDirectory;
              holds = home.path;
              setBy = if externalPackageInstall then "machine" else "activation";
            };
          };
        };

      configuration =
        variant: args:
        selection.mkModuleConfiguration {
          selection = {
            class = "homeManager";
            inherit args;
          };
          type = "home-manager";
          # A home-manager configuration is evaluated per system: it
          # has an evaluation result for each system its parent
          # evaluates its children for.
          perSystem = true;
          defaultPkgs = args.defaultPkgs or null;
          inherit exportsTo;
          # A home-manager configuration is activated for its user. Its
          # identity is its activation package; its marker is a file
          # under `$HOME/.local/state`, named by `$HOME` and not by
          # `$XDG_STATE_HOME`, which a unit of a NixOS configuration and a shell
          # may see differently. The home-manager module
          # `activation-marker` writes. The configurations with an
          # activation declared inside the home-manager configuration
          # check it. Its profile adapter (`profileAdapter`) says where
          # its profiles are and what sets each.
          activation = {
            identity = manifest: manifest.outputs.activationPackage.outPath;
            marker = manifest: "$HOME/.local/state/caisson/markers/${selection.markerFileName manifest}";
            inherit profileAdapter;
          };
          # Each evaluation result of a home-manager configuration
          # checks that its activation package builds, the package
          # `home-manager switch` builds and activates.
          checks =
            { outputs, ... }:
            {
              activation = {
                derivation = outputs.activationPackage;
                category = "build";
                description = "the activation package of the home-manager configuration builds";
              };
            };
          evaluate = evaluation variant args;
        };

      integration = selection.mkIntegration {
        name = "home-manager";
        class = "homeManager";
        # A home-manager configuration that is a caisson top, as the
        # home-manager CLI reads it: the evaluated home-manager
        # configuration, with its `activationPackage`. Where the
        # composition declares several systems, it is the evaluated
        # home-manager configurations by system, and where it has none,
        # the empty set (`integrations.topValue`).
        top = selection.topValue;
        # What these return is a configuration, a function of
        # `{ name, parent }`: a parent that declares it under
        # `caisson.home-manager.configurations.<name>` finalizes it,
        # and `mkTopConfiguration` finalizes it at a caisson top.
        # `lib.caisson.home-manager-minimal` takes the same arguments.
        # The home-manager configuration is evaluated per system, once
        # for each system its parent evaluates its children for, and its
        # package sets come from the composition, through the manifest;
        # `defaultPkgs` selects the set it runs on.
        mkConfiguration =
          {
            # The module of the home-manager configuration. When
            # absent, the configuration registered under its name
            # (`lib.caisson.configs.homeManager.<name>`), if any.
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
            # The package set the home-manager configuration runs on:
            # a function that receives the package sets available
            # where it is declared, as an attribute set by package
            # config name, each for the system it is evaluated for, and
            # returns the set to run on. When absent, the selection of
            # the nearest
            # configuration above, which inside a NixOS configuration
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
            # a home-manager configuration declared inside a NixOS
            # configuration gets the configuration of that NixOS
            # configuration, and any other home-manager configuration
            # gets null.
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
    {
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
