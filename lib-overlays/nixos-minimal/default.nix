# SPDX-License-Identifier: MIT
#
# The nixos-minimal integration: the minimal NixOS evaluator,
# `evalModules` from nixos/lib with no NixOS base modules, as a second
# integration over the `nixos` module class, which the nixos
# integration owns. It carries the constructors only. The class, its
# registration form (`lib.caisson.nixos.mkModule`), its framework
# module and its default default belong to the nixos integration, and
# the module list is composed by that integration
# (`lib.caisson.nixos.compose`), so the two evaluators cannot express
# different machines from the same arguments. With no base modules,
# the config module declares every option it uses, and the package
# set arrives as the `pkgs` module argument rather than through
# `nixpkgs.pkgs`.
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
      # The integration whose class this one evaluates.
      over =
        final.caisson.nixos
          or (throw "lib.caisson.nixos-minimal evaluates the nixos class and needs the nixos integration composed beside it.");

      commonAccepted = [
        "ecosystemSrc"
        "pkgSets"
        "configModule"
        "moduleImports"
        "specialArgs"
      ];
      hints = {
        modules = "pass the configuration's module as `configModule`; registered class modules are selected with `moduleImports`.";
        pkgs = "pass the package set as `pkgSets.pkgs`.";
        baseModules = "the minimal evaluator takes no base modules; lib.caisson.nixos.mkConfiguration evaluates with NixOS' module list.";
      };
      mkCheck =
        name: extra: open:
        final.caisson.integrations.checkArgs {
          context = "lib.caisson.nixos-minimal.${name}";
          accepted = commonAccepted ++ extra;
          inherit hints open;
        };

      compose = over.compose {
        context = "lib.caisson.nixos-minimal.mkConfiguration";
        nixpkgsModule = false;
      };

      evalArgs = args: common: {
        prefix = args.prefix or [ ];
        modules = common.modules;
        specialArgs = common.specialArgs;
      };
      evaluate = common: (import "${common.src}/nixos/lib" { }).evalModules;

      mkConfiguration =
        rawArgs:
        let
          args = mkCheck "mkConfiguration" [
            "prefix"
          ] "lib.caisson.nixos-minimal.mkConfigurationWithEcosystemArgs" rawArgs;
          common = compose args;
        in
        evaluate common (evalArgs args common);

      # The same composition, then `ecosystemArgs` merged over the
      # evalModules call verbatim: everything nixos/lib's evalModules
      # takes (prefix, modules, specialArgs) can be set or replaced
      # there.
      mkConfigurationWithEcosystemArgs =
        rawArgs:
        let
          args = mkCheck "mkConfigurationWithEcosystemArgs" [ "prefix" "ecosystemArgs" ] null rawArgs;
          common = compose args;
        in
        evaluate common (evalArgs args common // (args.ecosystemArgs or { }));
    in
    {
      caisson = (prev.caisson or { }) // {
        nixos-minimal = ((prev.caisson or { }).nixos-minimal or { }) // {
          inherit mkConfiguration mkConfigurationWithEcosystemArgs;
        };
      };
    };

}
