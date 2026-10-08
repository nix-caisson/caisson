# SPDX-License-Identifier: MIT
#
# The home-manager-minimal integration, declared as an alt over the
# home-manager integration: home-manager's minimal module list, the
# necessary modules alone, over the `homeManager` class that
# integration owns. It carries constructors only: the class, its
# registration form and its composition belong to
# `lib.caisson.home-manager`. A configuration evaluated here imports
# the modules it uses itself, from the `modulesPath` special argument
# the evaluation supplies.
{ mkLibOverlay, ... }:
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
      over =
        final.caisson.home-manager
          or (throw "lib.caisson.home-manager-minimal evaluates the homeManager class and needs the home-manager integration composed beside it.");

      # In the tree an evaluation of an alt is a configuration of the
      # integration that owns the class: it is declared under
      # `caisson.home-manager.configurations` and published where
      # homes are.
      configuration = over.configuration {
        context = "lib.caisson.home-manager-minimal.mkConfiguration";
        minimal = true;
      };
    in
    {
      caisson = (prev.caisson or { }) // {
        home-manager-minimal = final.caisson.integrations.mkAltIntegration {
          inherit over;
          # The arguments of `lib.caisson.home-manager.mkConfiguration`,
          # documented there, and the same result: a configuration, a
          # function of `{ name, parent }`. This entry point evaluates
          # with the necessary modules alone;
          # lib.caisson.home-manager.mkConfiguration evaluates with
          # home-manager's whole module tree.
          mkConfiguration =
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
              osConfig ? null,
              check ? null,
              sourceMeta ? null,
              ecosystemArgs ? null,
            }@args:
            configuration args;
          extra = {
            # A minimal home that is a top, as
            # `lib.caisson.home-manager.mkTopConfiguration` returns it.
            mkTopConfiguration =
              rawArgs:
              final.caisson.integrations.topValue (
                final.caisson-core.finalizeTop (final.caisson.home-manager-minimal.mkConfiguration rawArgs)
              );
          };
        };
      };
    };

}
