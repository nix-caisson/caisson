# SPDX-License-Identifier: MIT
#
# The nixvim integration: it owns the `nixvim` class, the class of
# nixvim's modules. A nixvim configuration is a Neovim, written as
# nixvim modules (`plugins.*`, `opts`, `keymaps`), evaluated per
# system, once for each system in force where it is declared, on the package set selected for
# it.
#
# nixvim evaluates its modules with `evalNixvim`: `evalModules` over
# `modules/top-level`, on a library extended with the overlay nixvim
# publishes, `lib.overlay`, which adds `lib.nixvim`. caisson makes the
# same evaluation on the composed library extended with that overlay,
# with `nixpkgs.pkgs` set to the selected package set and the nixvim
# flake as `flake`, as `evalNixvim` sets it. So the integration needs
# the nixvim flake.
#
# The output is `package`, the Neovim, `config.build.package`. A
# configuration is published as `nixvimConfigurations.<system>.<name>`,
# the evaluated configuration, under the name nixvim's flake publishes
# its own configurations under.
#
# A nixvim configuration is kept in a Nix profile of its own, as an nvf
# configuration is (`lib.caisson.integrations.profileOf`): its output
# `activationPackage` holds `activate`, and the configuration it is
# declared inside activates it with the module `profile-activation` of
# its class.
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
      context = "lib.caisson.nixvim.mkConfiguration";

      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc {
        name = "nixvim";
        context = "caisson.nixvim";
      };

      # A nixvim source: the nixvim flake, which publishes its library
      # overlay as `lib.overlay` and holds its modules at
      # `modules/top-level`.
      assertNixvimSrc =
        ecosystemSrc:
        if
          builtins.isAttrs ecosystemSrc
          && (ecosystemSrc.lib or { }) ? overlay
          && builtins.pathExists "${ecosystemSrc}/modules/top-level"
        then
          ecosystemSrc
        else
          throw "${context} requires `ecosystemSrc` to be the nixvim flake (publishing lib.overlay, holding modules/top-level).";

      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;
          src = assertNixvimSrc (resolveEcosystemSrc {
            explicit = args.ecosystemSrc or null;
            manifest = lib.caisson-core.libManifest or { };
          });

          name = manifest.name or null;
          inherit (manifest) system;
          what =
            if name != null then
              "the nixvim configuration `${name}` for ${system}"
            else
              "this nixvim configuration for ${system}";

          pkgSets = selection.pkgSetsForSystem { inherit context what; } manifest system;
          pkgs = selection.pkgSetOf { inherit context what; } manifest pkgSets;

          # The composed library extended with the overlay nixvim
          # publishes. `extend` extends the library of nixpkgs, so the
          # composed library is laid over it again, with the module
          # system of the extension, before the overlay.
          nixvimLib = lib.extend (
            self: super:
            lib
            // {
              inherit (super) modules types evalModules;
            }
            // src.lib.overlay self super
          );

          registry = lib.caisson.modules.nixvim or { };
          frameworkModules = selection.frameworkModules "nixvim" registry;
          moduleImports = selection.moduleImportsOf "nixvim" { inherit lib manifest; } args;

          # The configuration's module: the module passed, else the
          # configuration registered under the configuration's name
          # (`configs/nixvim/<name>`), else none.
          registered = lib.caisson.configs.nixvim or { };
          configModule =
            if (args.configModule or null) != null then
              args.configModule
            else if name != null then
              registered.${name} or null
            else
              null;

          value = nixvimLib.evalModules (
            {
              class = "nixvim";
              specialArgs = {
                inherit pkgSets;
                lib = nixvimLib;
                modulesPath = "${src}/modules";
              }
              // (if (args.specialArgs or null) != null then args.specialArgs else { });
              modules =
                frameworkModules
                ++ moduleImports registry
                ++ (if configModule == null then [ ] else [ configModule ])
                ++ [
                  "${src}/modules/top-level"
                  {
                    _file = "caisson-nixvim:evalNixvim";
                    flake = nixvimLib.mkOptionDefault src;
                    nixpkgs.pkgs = pkgs;
                  }
                ];
            }
            // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { })
          );
          package = value.config.build.package;
          kept = selection.profileOf {
            inherit pkgs manifest package;
            kind = "nixvim";
            # The programs the Neovim has in `bin`: `nvim`, and `vi`
            # and `vim` when nixvim adds them.
            programs = [
              "nvim"
            ]
            ++ (if value.config.viAlias or false then [ "vi" ] else [ ])
            ++ (if value.config.vimAlias or false then [ "vim" ] else [ ]);
            variable = "CAISSON_NVIM_PROFILE";
            warn = value.config.caisson.drift.warn or true;
          };
        in
        {
          inherit value;
          outputs = {
            inherit package;
            inherit (kept) activationPackage profile;
          };
        };

      # A nixvim configuration is published as
      # `nixvimConfigurations.<system>.<name>`, the evaluated
      # configuration.
      exportsTo = {
        attrset = "nixvimConfigurations";
        bySystem = true;
        value = manifest: manifest.value;
      };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          type = "nixvim";
          # A nixvim configuration is evaluated per system: it has an
          # evaluation for every system in force where it is declared.
          perSystem = true;
          defaultPkgs = args.defaultPkgs or null;
          inherit exportsTo;
          # A nixvim configuration is activated into its profile. Its
          # identity is its Neovim.
          activation = {
            identity = manifest: manifest.outputs.package.outPath;
            marker = manifest: "${manifest.outputs.profile.path}.marker.json";
          };
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "nixvim";
        class = "nixvim";
        # A nixvim configuration that is a top, as a tool reads it: the
        # evaluation, or the evaluations by system where several are in
        # force.
        top = final.caisson.integrations.topValue;
        # What these return is a configuration, a function of
        # `{ name, parent }`: a parent that declares it under
        # `caisson.nixvim.configurations.<name>` finalizes it, and
        # `mkTopConfiguration` finalizes it at a top.
        mkConfiguration =
          {
            # The configuration's module. When absent, the configuration
            # registered under the configuration's name
            # (`lib.caisson.configs.nixvim.<name>`), if any. Further
            # modules of the class are selected with `moduleImports`,
            # from the registry.
            configModule ? null,
            # The nixvim flake; resolved from the composition's
            # declarations when absent.
            ecosystemSrc ? null,
            # The package set the configuration runs on: a function
            # that receives the package sets available where it is
            # declared, by package config name, each for the system of
            # the evaluation, and returns the set to run on. When
            # absent, the selection of the nearest configuration above,
            # and the set named `default` where none above selects.
            defaultPkgs ? null,
            # The selection over the nixvim class of the registry. It
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
        nixvim = integration.namespace;
      };
    };

}
