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
        final.caisson.home-manager
          or (throw "lib.caisson.home-manager-minimal evaluates the homeManager class and needs the home-manager integration composed beside it.");
    in
    {
      caisson = (prev.caisson or { }) // {
        home-manager-minimal = final.caisson.integrations.mkAltIntegration {
          name = "home-manager-minimal";
          inherit over;
          accepted = [
            "osConfig"
            "check"
            "sourceMeta"
          ];
          hints = {
            configuration = "pass the configuration's module as `configModule`; registered class modules are selected with `moduleImports`.";
            pkgs = "pass the package set as `pkgSets.pkgs`.";
            extraSpecialArgs = "pass extra module arguments as `specialArgs`.";
            minimal = "this entry point is the minimal module list; lib.caisson.home-manager.mkConfiguration evaluates with home-manager's whole module tree.";
          };
          compose = over.compose {
            context = "lib.caisson.home-manager-minimal.mkConfiguration";
            minimal = true;
          };
          inherit (over) evaluate;
        };
      };
    };

}
