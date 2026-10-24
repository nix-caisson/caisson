# SPDX-License-Identifier: MIT
#
# The darwin integration: it owns the `darwin` class and evaluates it
# with nix-darwin's `eval-config.nix`, over the composed library. A
# darwin configuration is a macOS machine, evaluated per system,
# once for each system in force where it is declared, as a NixOS configuration is, and
# published as `darwinConfigurations.<name>`, the value `darwin-rebuild`
# reads: the evaluated configuration with its `system` beside it.
#
# The evaluation is the one nix-darwin's `darwinSystem` makes: the
# configuration's modules with nix-darwin's module list, and the
# settings `darwinSystem` adds to them, `nixpkgs.source` from the
# nixpkgs the composition declares, no check of `NIX_PATH`, and the
# revision of the nix-darwin source in the version of the system. The
# package set is the one caisson selects for the configuration, as for
# a NixOS configuration, handed to nix-darwin's `nixpkgs.pkgs`.
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
      context = "lib.caisson.darwin.mkConfiguration";

      resolveDarwinSrc = final.caisson.integrations.resolveEcosystemSrc darwinEcosystem;
      darwinAccountOf = final.caisson.integrations.ecosystemAccountOf darwinEcosystem;
      darwinEcosystem = {
        name = "nix-darwin";
        context = "caisson.darwin";
      };

      resolveNixpkgsSrc = final.caisson.integrations.resolveEcosystemSrc nixpkgsEcosystem;
      nixpkgsAccountOf = final.caisson.integrations.ecosystemAccountOf nixpkgsEcosystem;
      nixpkgsEcosystem = {
        name = "nixpkgs";
        context = "caisson.darwin";
      };

      # A nix-darwin source: the nix-darwin flake or source tree, which
      # holds the evaluator at `eval-config.nix`.
      assertDarwinSrc =
        ecosystemSrc:
        let
          path = if builtins.isAttrs ecosystemSrc then ecosystemSrc.outPath or null else ecosystemSrc;
        in
        if path != null && builtins.pathExists "${path}/eval-config.nix" then
          ecosystemSrc
        else
          throw "${context} requires `ecosystemSrc` to be a nix-darwin flake or source tree (holding eval-config.nix).";

      # The evaluator's call, on the view being evaluated: eval-config
      # over the framework modules, the selection, the configuration's
      # module and the settings of `darwinSystem`, for the
      # configuration's system. `ecosystemArgs`, which only the twin's
      # pattern admits, is merged over the call last.
      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;
          libManifest = lib.caisson-core.libManifest or { };
          src = assertDarwinSrc (resolveDarwinSrc {
            explicit = args.ecosystemSrc or null;
            manifest = libManifest;
          });
          nixpkgsSrc = resolveNixpkgsSrc { manifest = libManifest; };

          name = manifest.name or null;
          inherit (manifest) system;
          what =
            if name != null then
              "the darwin configuration `${name}` for ${system}"
            else
              "this darwin configuration for ${system}";

          # The package sets available to the configuration, each for the
          # system of the evaluation, and the one it runs on.
          pkgSets = selection.pkgSetsForSystem { inherit context what; } manifest system;
          pkgs = selection.pkgSetOf { inherit context what; } manifest pkgSets;

          registry = lib.caisson.modules.darwin or { };
          frameworkModules = selection.frameworkModules "darwin" registry;
          moduleImports = selection.moduleImportsOf "darwin" { inherit lib manifest; } args;

          # The configuration's module: the module passed, else the
          # configuration registered under the configuration's name
          # (`configs/darwin/<name>`), else none.
          registered = lib.caisson.configs.darwin or { };
          configModule =
            if (args.configModule or null) != null then
              args.configModule
            else if name != null then
              registered.${name} or null
            else
              null;

          # What `darwinSystem` adds to the modules of a configuration,
          # with the package set caisson selects.
          darwinSystemModule =
            { lib, ... }:
            {
              _file = "caisson-darwin:darwinSystem";
              nixpkgs.pkgs = pkgs;
              nixpkgs.hostPlatform = lib.mkDefault system;
              nixpkgs.source = lib.mkDefault nixpkgsSrc;
              nixpkgs.flake.source = lib.mkDefault (nixpkgsSrc.outPath or (toString nixpkgsSrc));
              system.checks.verifyNixPath = lib.mkDefault false;
              system.darwinVersionSuffix = ".${src.shortRev or src.dirtyShortRev or "dirty"}";
              system.darwinRevision =
                let
                  rev = src.rev or src.dirtyRev or null;
                in
                lib.mkIf (rev != null) rev;
            };

          darwinModules =
            frameworkModules
            ++ moduleImports registry
            ++ (if configModule == null then [ ] else [ configModule ])
            ++ [ darwinSystemModule ];

          value = import "${src}/eval-config.nix" (
            {
              inherit lib;
              modules = darwinModules;
              # The package sets for the configuration's system, by
              # config name, and the composed library, which is what
              # the modules receive as `lib`.
              specialArgs = {
                inherit lib pkgSets;
              }
              // (if (args.specialArgs or null) != null then args.specialArgs else { });
            }
            // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { })
          );
        in
        {
          inherit value;
          # Where nix-darwin came from, as `src` was resolved, and where
          # the nixpkgs of `nixpkgs.source` came from, as `nixpkgsSrc`
          # was resolved.
          ecosystems = {
            nix-darwin = darwinAccountOf {
              explicit = args.ecosystemSrc or null;
              manifest = libManifest;
            };
            nixpkgs = nixpkgsAccountOf { manifest = libManifest; };
          };
          # What eval-config received: the modules of the
          # composition, then nix-darwin's module list.
          modules = darwinModules ++ [
            (final.caisson.integrations.ecosystemUnit {
              key = "nix-darwin";
              project = "nix-darwin";
              file = "modules/module-list.nix";
            })
          ];
          # What `darwin-rebuild` builds: the closure of the system.
          outputs.toplevel = value.config.system.build.toplevel;
        };

      # A darwin configuration is published as
      # `darwinConfigurations.<name>`, the evaluated configuration with
      # `system` beside `config`, which is what `darwin-rebuild` reads.
      exportsTo = {
        attrset = "darwinConfigurations";
        value = manifest: manifest.value;
      };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          selection = {
            class = "darwin";
            inherit args;
          };
          type = "darwin";
          # A darwin configuration is evaluated per system: it has an
          # evaluation for every system in force where it is declared.
          perSystem = true;
          defaultPkgs = args.defaultPkgs or null;
          inherit exportsTo;
          # A darwin configuration is activated on a machine; the
          # configurations with an activation declared inside it check
          # its marker.
          activation = final.caisson.integrations.machineActivation;
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "darwin";
        class = "darwin";
        # A darwin configuration that is a top, as a tool reads it: the
        # evaluated configuration, or the evaluated configurations by
        # system where several are in force, as for NixOS.
        top = final.caisson.integrations.topValue;
        # What these return is a configuration, a function of
        # `{ name, parent }`: a parent that declares it under
        # `caisson.darwin.configurations.<name>` finalizes it, and
        # `mkTopConfiguration` finalizes it at a top.
        mkConfiguration =
          {
            # The configuration's module. When absent, the configuration
            # registered under the configuration's name
            # (`lib.caisson.configs.darwin.<name>`), if any. Further
            # modules of the class are selected with `moduleImports`,
            # from the registry.
            configModule ? null,
            # The nix-darwin flake or source tree; resolved from the
            # composition's declarations when absent.
            ecosystemSrc ? null,
            # The package set the configuration runs on: a function
            # that receives the package sets available where it is
            # declared, by package config name, each for the system of
            # the evaluation, and returns the set to run on. When
            # absent, the selection of the nearest configuration above,
            # and the set named `default` where none above selects.
            defaultPkgs ? null,
            # The selection over the darwin class of the registry. It
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
        darwin = integration.namespace;
      };
    };

}
