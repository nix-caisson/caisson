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
    in
    {
      caisson = (prev.caisson or { }) // {
        nixos-minimal = final.caisson.integrations.mkAltIntegration {
          name = "nixos-minimal";
          inherit over;
          accepted = [ "prefix" ];
          hints = {
            pkgs = "pass the package set as `pkgSets.pkgs`.";
            baseModules = "the minimal evaluator takes no base modules; lib.caisson.nixos.mkConfiguration evaluates with NixOS' module list.";
          };
          compose =
            args:
            let
              common = over.compose {
                context = "lib.caisson.nixos-minimal.mkConfiguration";
                nixpkgsModule = false;
              } args;
            in
            common
            // {
              ecosystemArgs = {
                prefix = args.prefix or [ ];
                modules = common.modules;
                specialArgs = common.specialArgs;
                # `nixos/lib/default.nix` of the nixpkgs source takes
                # `lib` and defaults it to `import ../../lib`, the
                # library of the tree it lives in. It is the argument
                # of that file rather than of `evalModules`, so
                # `evaluate` reads it out of the call and hands it to
                # the import; the twin replaces it like any other
                # evaluator argument.
                lib = common.lib;
              };
            };
          evaluate =
            composed: callArgs:
            (import "${composed.src}/nixos/lib" {
              inherit (callArgs) lib;
            }).evalModules
              (builtins.removeAttrs callArgs [ "lib" ]);
        };
      };
    };

}
