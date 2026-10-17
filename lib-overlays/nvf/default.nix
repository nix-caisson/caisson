# SPDX-License-Identifier: MIT
#
# The nvf integration: it owns the `nvf` class, the class of nvf's
# modules. An nvf configuration is a Neovim, written as nvf modules
# (`vim.*`), evaluated at every system in force where it is declared,
# on the package set selected for it.
#
# nvf evaluates its modules with `neovimConfiguration`, on nixpkgs'
# library extended with nvf's own, `lib.nvim`. caisson evaluates the
# same modules, nvf's `modules/modules.nix`, with the special arguments
# `neovimConfiguration` passes (`self` and `inputs`, the nvf flake, and
# `modulesPath`), on the composed library extended with `lib.nvim`
# built from the same nvf source. So the integration needs the nvf
# flake, whose inputs nvf's modules read.
#
# The output is `neovim`, the wrapped Neovim, the `neovim` that
# `neovimConfiguration` returns. A configuration is published as
# `packages.<system>.<name>`.
#
# An nvf configuration is kept in a Nix profile of its own, the way a
# home keeps its generations (`lib.caisson.integrations.profileOf`):
# its output `activationPackage` holds `activate`, which points the
# profile at the Neovim, and `profile` says where the profile is. A
# machine, a home or a hjem configuration activates the nvf
# configurations declared inside it each time it is activated itself,
# with the module `profile-activation` of its class.
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
      context = "lib.caisson.nvf.mkConfiguration";

      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc {
        name = "nvf";
        context = "caisson.nvf";
      };

      # An nvf source: the nvf flake, which holds its library at `lib`,
      # its modules at `modules/modules.nix`, and the inputs its modules
      # read.
      assertNvfSrc =
        ecosystemSrc:
        if
          builtins.isAttrs ecosystemSrc
          && ecosystemSrc ? inputs
          && builtins.pathExists "${ecosystemSrc}/modules/modules.nix"
          && builtins.pathExists "${ecosystemSrc}/lib/default.nix"
        then
          ecosystemSrc
        else
          throw "${context} requires `ecosystemSrc` to be the nvf flake (with its inputs, holding modules/modules.nix and lib/default.nix).";

      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;
          src = assertNvfSrc (resolveEcosystemSrc {
            explicit = args.ecosystemSrc or null;
            manifest = lib.caisson-core.libManifest or { };
          });
          # The inputs nvf's modules read, with the flake as `self`, as a
          # flake's `outputs` receives them.
          inputs = src.inputs // {
            self = src;
          };

          name = manifest.name or null;
          inherit (manifest) system;
          what =
            if name != null then
              "the nvf configuration `${name}` at ${system}"
            else
              "this nvf configuration at ${system}";

          pkgSets = selection.pkgSetsAt { inherit context what; } manifest system;
          pkgs = selection.pkgSetOf { inherit context what; } manifest pkgSets;

          # The composed library extended with the library of nvf, as
          # `lib/stdlib-extended.nix` of nvf extends the library of
          # nixpkgs. `extend` extends the library of nixpkgs, so the
          # composed library is laid over it again, with the module
          # system of the extension, as the home-manager integration lays
          # it for `lib.hm`.
          nvfLib = lib.extend (
            self: super:
            lib
            // {
              inherit (super) modules types evalModules;
              nvim = import "${src}/lib" {
                inherit inputs;
                self = src;
                lib = self;
              };
              literalExpression = super.literalExpression or super.literalExample;
            }
          );

          registry = lib.caisson.modules.nvf or { };
          frameworkModules = selection.frameworkModules "nvf" registry;
          moduleImports = selection.moduleImportsOf "nvf" { inherit lib manifest; } args;

          # The configuration's module: the module passed, else the
          # configuration registered under the configuration's name
          # (`configs/nvf/<name>`), else none.
          registered = lib.caisson.configs.nvf or { };
          configModule =
            if (args.configModule or null) != null then
              args.configModule
            else if name != null then
              registered.${name} or null
            else
              null;

          value = nvfLib.evalModules (
            {
              class = "nvf";
              specialArgs = {
                inherit inputs pkgSets;
                self = src;
                modulesPath = toString "${src}/modules";
                lib = nvfLib;
              }
              // (if (args.specialArgs or null) != null then args.specialArgs else { });
              modules =
                import "${src}/modules/modules.nix" {
                  inherit pkgs;
                  lib = nvfLib;
                }
                ++ frameworkModules
                ++ moduleImports registry
                ++ (if configModule == null then [ ] else [ configModule ]);
            }
            // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { })
          );
          neovim = value.config.vim.build.finalPackage;
          kept = selection.profileOf {
            inherit pkgs manifest;
            kind = "nvf";
            package = neovim;
            # The programs the Neovim has in `bin`: `nvim`, and `vi`
            # and `vim` when nvf adds them.
            programs = [
              "nvim"
            ]
            ++ (if value.config.vim.viAlias then [ "vi" ] else [ ])
            ++ (if value.config.vim.vimAlias then [ "vim" ] else [ ]);
            variable = "CAISSON_NVIM_PROFILE";
            warn = value.config.caisson.drift.warn or true;
          };
        in
        {
          inherit value;
          outputs = {
            inherit neovim;
            inherit (kept) activationPackage profile;
          };
        };

      # An nvf configuration is published as `packages.<system>.<name>`,
      # its Neovim.
      exportsTo = {
        attrset = "packages";
        bySystem = true;
        value = manifest: manifest.outputs.neovim;
      };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          type = "nvf";
          # An nvf configuration is evaluated per system: it has an
          # evaluation for every system in force where it is declared.
          perSystem = true;
          defaultPkgs = args.defaultPkgs or null;
          inherit exportsTo;
          # An nvf configuration is activated into its profile. Its
          # identity is its Neovim.
          activation = {
            identity = manifest: manifest.outputs.neovim.outPath;
            marker = manifest: "${manifest.outputs.profile.path}.marker.json";
          };
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "nvf";
        class = "nvf";
        # An nvf configuration that is a top, as a tool reads it: the
        # evaluation, or the evaluations by system where several are in
        # force.
        top = final.caisson.integrations.topValue;
        # What these return is a configuration, a function of
        # `{ name, parent }`: a parent that declares it under
        # `caisson.nvf.configurations.<name>` finalizes it, and
        # `mkTopConfiguration` finalizes it at a top.
        mkConfiguration =
          {
            # The configuration's module. When absent, the configuration
            # registered under the configuration's name
            # (`lib.caisson.configs.nvf.<name>`), if any. Further modules
            # of the class are selected with `moduleImports`, from the
            # registry.
            configModule ? null,
            # The nvf flake; resolved from the composition's
            # declarations when absent.
            ecosystemSrc ? null,
            # The package set the configuration runs on: a function
            # that receives the package sets available where it is
            # declared, by package config name, each at the system of
            # the evaluation, and returns the set to run on. When
            # absent, the selection of the nearest configuration above,
            # and the set named `default` where none above selects.
            defaultPkgs ? null,
            # The selection over the nvf class of the registry. It
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
            ecosystemArgs ? null,
          }@args:
          configuration args;
      };
    in
    {
      caisson = (prev.caisson or { }) // {
        nvf = integration.namespace;
      };
    };

}
