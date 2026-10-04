# SPDX-License-Identifier: MIT
#
# The composition the nixos integration's entry points share, and the
# nixos-minimal integration reads through `lib.caisson.nixos.compose`:
# the definition of the library, the module list, the special
# arguments, the system and the package set, so the evaluators of the
# class cannot express different machines from the same arguments.
#
# It is a function of the view being evaluated: `lib`, the library the
# evaluation runs on, and `manifest`, the manifest of the evaluation.
# A NixOS configuration has an evaluation for every system in force
# where it is declared, so the manifest is that of an evaluation at a
# system: the name, the system and the package sets come from it.
{
  context,
  # Whether the evaluation carries NixOS' nixpkgs module.
  nixpkgsModule ? true,
}:
{ lib, manifest }:
args:
let
  selection = lib.caisson.integrations;

  # The name of the configuration this is an evaluation of.
  name = manifest.name or null;

  # The system of this evaluation.
  inherit (manifest) system;

  what =
    if name != null then
      "the NixOS configuration `${name}` at ${system}"
    else
      "this NixOS configuration at ${system}";

  # The package configs visible to the configuration, each projected
  # to its set at the configuration's system, by config name.
  configs = manifest.pkgSets or { };
  pkgSets = builtins.mapAttrs (
    name: config:
    (config.children.nixpkgs.${system} or (throw ''
      ${context}: the package config `${name}` builds no set for ${system},
      which ${what} needs. Add the system to `caisson.nixpkgs.systems`
      in the config's module.
    '')
    ).value
  ) configs;

  selected =
    name:
    pkgSets.${name} or (throw ''
      ${context}: ${what} selects the package config `${name}`
      (`caisson.nixpkgs.pkgSet`), and the composition declares ${
        if configs == { } then
          "no package configs"
        else
          "the package configs " + builtins.concatStringsSep ", " (builtins.attrNames configs)
      }. Declare it with `pkgSets` on caisson-core.mkLib.
    '');

  # The package set the configuration runs on is an option of the
  # configuration, so any of its modules may define it and it merges
  # as options do. eval-config evaluations carry the nixpkgs module,
  # so the set lands on `nixpkgs.pkgs`; an evaluation without that
  # module takes it as the `pkgs` module argument instead.
  pkgSetModule =
    { config, lib, ... }:
    {
      _file = "caisson-nixos:pkgSet";
      options.caisson.nixpkgs.pkgSet = lib.mkOption {
        type = lib.types.str;
        default = "default";
        description = ''
          The package config whose set this configuration runs on, by
          the name it is declared under in `pkgSets` on
          caisson-core.mkLib. The set is that config's set at the
          configuration's system.
        '';
      };
      config =
        if nixpkgsModule then
          { nixpkgs.pkgs = selected config.caisson.nixpkgs.pkgSet; }
        else
          { _module.args.pkgs = lib.mkDefault (selected config.caisson.nixpkgs.pkgSet); };
    };

  registry = lib.caisson-core.modules.nixos or { };
  # The framework module of the class, forced.
  coreModules = selection.frameworkModules "nixos" registry;
  moduleImports = selection.moduleImportsOf "nixos" { inherit lib manifest; } args;

  # The configuration's module: the module passed, else the
  # configuration registered under the configuration's name
  # (`configs/nixos/<name>`), else none.
  registered = lib.caisson-core.configs.nixos or { };
  configModule =
    if (args.configModule or null) != null then
      args.configModule
    else if name != null then
      registered.${name} or null
    else
      null;
in
{
  inherit system pkgSets;
  # The composed library is what a NixOS evaluation of this class runs
  # on, whichever evaluator of the class performs it.
  inherit lib;
  modules =
    coreModules
    ++ moduleImports registry
    ++ (if configModule == null then [ ] else [ configModule ])
    ++ [ pkgSetModule ];
  # Framework defaults first; the caller's win on conflict, as is
  # normal in the Nix ecosystem.
  specialArgs = {
    # The package sets at the configuration's system, by config name.
    inherit pkgSets;
    # The `lib` argument every module receives. `evalModules` builds
    # that argument from the `lib` its `lib/modules.nix` closed
    # over, which is the fixpoint the `nixpkgs-lib` entry read rather
    # than the library this composition built, and `// specialArgs` in
    # that file is where a caller says otherwise. Naming it here is
    # what puts the composed library in front of the modules.
    inherit lib;
  }
  // (if (args.specialArgs or null) != null then args.specialArgs else { });
}
