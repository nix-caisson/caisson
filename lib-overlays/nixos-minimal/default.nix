# SPDX-License-Identifier: MIT
#
# The nixos-minimal integration, declared as an alt over the nixos
# integration: the minimal NixOS evaluator, `evalModules` from
# nixos/lib with no NixOS base modules, over the `nixos` class that
# integration owns and over the composed library. It carries
# constructors only: the class, its registration form and its
# composition belong to `lib.caisson.nixos`.
# With no base modules, the config module declares every option it
# uses, and the package set arrives as the `pkgs` module argument
# rather than through `nixpkgs.pkgs`.
{ entries, mkLibOverlay, ... }:
{

  imports = [
    entries.nixpkgs-lib
    # What an integration is written from, imported by key so it is
    # composed wherever this integration is.
    ((mkLibOverlay ../integrations) // { key = "integrations"; })
  ];

  overlay =
    final: prev:
    let
      over =
        final.caisson.nixos
          or (throw "lib.caisson.nixos-minimal evaluates the nixos class and needs the nixos integration composed beside it.");

      # The evaluator's call, on the view being evaluated: `evalModules`
      # from nixos/lib over the composition of the nixos class.
      # `ecosystemArgs`, which only the twin's pattern admits, is
      # merged over the call last.
      evaluate =
        args: view:
        let
          common = over.compose {
            context = "lib.caisson.nixos-minimal.mkConfiguration";
            nixpkgsModule = false;
          } view args;
          callArgs = {
            prefix = if (args.prefix or null) == null then [ ] else args.prefix;
            modules = common.modules;
            specialArgs = common.specialArgs;
            # `nixos/lib/default.nix` of the nixpkgs source takes
            # `lib` and defaults it to `import ../../lib`, the
            # library of the tree it lives in. It is the argument
            # of that file rather than of `evalModules`, so it is
            # read out of the call here and handed to the import;
            # the twin replaces it like any other evaluator
            # argument.
            lib = common.lib;
          }
          // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { });
        in
        {
          value =
            (import "${common.src}/nixos/lib" {
              inherit (callArgs) lib;
            }).evalModules
              (builtins.removeAttrs callArgs [ "lib" ]);
        };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          # In the tree an evaluation of an alt is a configuration of
          # the integration that owns the class: it is declared under
          # `caisson.nixos.configurations`, published where NixOS
          # configurations are, and `nearest.nixos` for what is beneath
          # it.
          type = "nixos";
          perSystem = true;
          defaultPkgs = args.defaultPkgs or null;
          inherit (over) exportsTo;
          evaluate = evaluate args;
        };
    in
    {
      caisson = (prev.caisson or { }) // {
        nixos-minimal = final.caisson.integrations.mkAltIntegration {
          inherit over;
          # The arguments of `lib.caisson.nixos.mkConfiguration`,
          # documented there, plus `prefix`, and the same result: a
          # configuration, a function of `{ name, parent }`. The
          # minimal evaluator takes no base modules;
          # lib.caisson.nixos.mkConfiguration evaluates with NixOS'
          # module list.
          mkConfiguration =
            {
              configModule ? null,
              ecosystemSrc ? null,
              defaultPkgs ? null,
              moduleImports ? null,
              extraModuleImports ? null,
              specialArgs ? null,
              # The `prefix` of evalModules, the option path the
              # evaluation sits at.
              prefix ? null,
            }@args:
            configuration args;
          mkConfigurationWithEcosystemArgs =
            {
              configModule ? null,
              ecosystemSrc ? null,
              defaultPkgs ? null,
              moduleImports ? null,
              extraModuleImports ? null,
              specialArgs ? null,
              prefix ? null,
              ecosystemArgs ? null,
            }@args:
            configuration args;
          extra = {
            # A minimal configuration that is a top, as
            # `lib.caisson.nixos.mkTopConfiguration` returns it.
            mkTopConfiguration =
              rawArgs:
              final.caisson.integrations.topValue (
                final.caisson-core.finalizeTop (final.caisson.nixos-minimal.mkConfiguration rawArgs)
              );
          };
        };
      };
    };

}
