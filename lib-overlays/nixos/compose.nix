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

  # The package sets available to the configuration, each at the
  # system of the evaluation, by package config name.
  pkgSets = selection.pkgSetsAt { inherit context what; } manifest system;

  # The set the configuration runs on, selected by the `pkgSet`
  # argument from those.
  pkgs = selection.pkgSetOf { inherit context what; } pkgSets args;

  # eval-config evaluations carry the nixpkgs module, so the set lands
  # on `nixpkgs.pkgs`; an evaluation without that module takes it as
  # the `pkgs` module argument instead.
  pkgSetModule =
    { lib, ... }:
    {
      _file = "caisson-nixos:pkgSet";
      config =
        if nixpkgsModule then { nixpkgs.pkgs = pkgs; } else { _module.args.pkgs = lib.mkDefault pkgs; };
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
