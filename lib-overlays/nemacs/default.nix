# SPDX-License-Identifier: MIT
#
# The nemacs integration: it owns the `nemacs` class, the class of the
# modules of nemacs. A nemacs configuration is an Emacs, written as
# nemacs modules (`bundles`, `init`, `packages`, `overrides`),
# evaluated per system, once for each system its parent evaluates its
# children for, on the package set selected for it.
#
# The integration needs no ecosystem source. The core module of nemacs
# is the module named `core` that the flake of nemacs registers for the
# class, and the evaluator is the module system on the composed
# library, with `pkgs` supplied as a module argument, as nemacs's own
# `evalNemacs` supplies it.
#
# The output is `package`, the editor, the `config.build.package` of
# the evaluation. A configuration is published as
# `nemacsConfigurations.<system>.<name>`: `package`, `activationPackage`,
# `config` and `options`, where `activationPackage` holds the `activate`
# of the profile described next.
#
# A nemacs configuration is kept in a separate Nix profile, the way a
# home-manager configuration keeps its generations
# (`lib.caisson.integrations.profileOf`): its output
# `activationPackage` holds `activate`, which points the profile at the
# editor, and `profile` says where the profile is. A NixOS, nix-darwin
# or system-manager configuration, a home-manager configuration or a
# hjem configuration activates the nemacs configurations declared
# inside it each time it is activated itself, with the module
# `profile-activation` of its class, and `activate` switches the
# editor alone.
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
      context = "lib.caisson.nemacs.mkConfiguration";

      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;

          name = manifest.name or null;
          inherit (manifest) system;
          what =
            if name != null then
              "the nemacs configuration `${name}` for ${system}"
            else
              "this nemacs configuration for ${system}";

          pkgSets = selection.pkgSetsForSystem { inherit context what; } manifest system;
          pkgs = selection.pkgSetOf { inherit context what; } manifest pkgSets;

          registry = lib.caisson.modules.nemacs or { };
          frameworkModules = selection.frameworkModules "nemacs" registry;
          moduleImports = selection.moduleImportsOf "nemacs" { inherit lib manifest; } args;

          # The configuration's module: the module passed, else the
          # configuration registered under the configuration's name
          # (`configs/nemacs/<name>`), else none.
          configModule = selection.configModuleOf {
            inherit lib name;
            class = "nemacs";
            configModule = args.configModule or null;
          };

          # The modules of the composition: the module that supplies
          # `pkgs`, the framework module of the class, the modules
          # selected from the registry, which include the core module of
          # nemacs, and the configuration's module.
          moduleList = [
            (selection.caissonModule {
              key = "caisson.nemacs.pkgs";
              file = "caisson-nemacs:pkgs";
              module = {
                _module.args.pkgs = pkgs;
              };
            })
          ]
          ++ frameworkModules
          ++ moduleImports registry
          ++ (if configModule == null then [ ] else [ configModule ]);

          value = lib.evalModules (
            {
              class = "nemacs";
              specialArgs = {
                inherit lib pkgSets;
              }
              // (if (args.specialArgs or null) != null then args.specialArgs else { });
              modules = moduleList;
            }
            // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { })
          );
          package = value.config.build.package;
          kept = selection.profileOf {
            inherit pkgs manifest package;
            kind = "nemacs";
            # The programs of the editor that a shell chooses among
            # profiles for.
            programs = [
              "emacs"
              "emacsclient"
            ];
            variable = "CAISSON_NEMACS_PROFILE";
            warn = value.config.caisson.drift.warn or true;
          };
        in
        {
          inherit value;
          # What evalModules received, in that order.
          modules = moduleList;
          outputs = {
            inherit package;
            inherit (kept) activationPackage profile;
          };
        };

      # A nemacs configuration is published as
      # `nemacsConfigurations.<system>.<name>`.
      exportsTo = {
        attrset = "nemacsConfigurations";
        bySystem = true;
        value = manifest: {
          inherit (manifest.outputs) package activationPackage;
          inherit (manifest.value) config options;
        };
      };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          selection = {
            class = "nemacs";
            inherit args;
          };
          type = "nemacs";
          # A nemacs configuration is evaluated per system: it has an
          # evaluation result for each system its parent evaluates its
          # children for.
          perSystem = true;
          defaultPkgs = args.defaultPkgs or null;
          inherit exportsTo;
          # A nemacs configuration is activated into its profile. Its
          # identity is its editor.
          activation = {
            identity = manifest: manifest.outputs.package.outPath;
            marker = manifest: "${manifest.outputs.profile.path}.marker.json";
          };
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "nemacs";
        class = "nemacs";
        # A nemacs configuration that is a top, as a tool reads it: the
        # evaluation, or the evaluations by system where several are in
        # force.
        top = final.caisson.integrations.topValue;
        # What these return is a configuration, a function of
        # `{ name, parent }`: a parent that declares it under
        # `caisson.nemacs.configurations.<name>` finalizes it, and
        # `mkTopConfiguration` finalizes it at a top.
        mkConfiguration =
          {
            # The configuration's module. When absent, the configuration
            # registered under the configuration's name
            # (`lib.caisson.configs.nemacs.<name>`), if any. Further
            # modules of the class are selected with `moduleImports`,
            # from the registry.
            configModule ? null,
            # The package set the configuration runs on: a function
            # that receives the package sets available where it is
            # declared, by package config name, each for the system of
            # the evaluation, and returns the set to run on. When
            # absent, the selection of the nearest configuration above,
            # and the set named `default` where none above selects.
            defaultPkgs ? null,
            # The selection over the nemacs class of the registry. It
            # replaces the default of the class, which is every entry
            # named `default` followed by what the configurations
            # above added.
            moduleImports ? null,
            # A selection added to that selection, whichever it is.
            extraModuleImports ? null,
            # Extra module arguments, merged over those the framework
            # supplies.
            specialArgs ? null,
          }@args:
          configuration args;
        # The same arguments, and `ecosystemArgs`: arguments for the
        # evaluator, merged over the composed call last.
        mkConfigurationWithEcosystemArgs =
          {
            configModule ? null,
            defaultPkgs ? null,
            moduleImports ? null,
            extraModuleImports ? null,
            specialArgs ? null,
            ecosystemArgs ? null,
          }@args:
          configuration args;
      };
    in
    {
      caisson = (prev.caisson or { }) // {
        nemacs = integration.namespace;
      };
    };

}
