# SPDX-License-Identifier: MIT
#
# The composition the nixos integration's entry points share, and the
# nixos-minimal integration reads through `lib.caisson.nixos.compose`:
# one definition of the module list and special arguments, so the
# evaluators of the class cannot express different machines from the
# same arguments.
{ final }:
let
  selection = final.caisson.integrations;

  assertPkgSets =
    context: pkgSets:
    if pkgSets ? pkgs then pkgSets else throw "${context} requires `pkgSets.pkgs` to be defined.";

  # eval-config evaluations carry the nixpkgs module, so the package
  # set lands on `nixpkgs.pkgs`; an evaluation without that module
  # takes it as the `pkgs` module argument instead.
  mkPkgSetsModule = pkgSets: {
    _file = "caisson-nixos:pkgSets";
    config = {
      nixpkgs.pkgs = pkgSets.pkgs;
    };
  };
  mkBarePkgSetsModule = pkgSets: {
    _file = "caisson-nixos:pkgSets-bare";
    config = {
      _module.args.pkgs = final.mkDefault pkgSets.pkgs;
    };
  };
in
{
  context,
  # Whether the evaluation carries NixOS' nixpkgs module.
  nixpkgsModule ? true,
}:
{
  pkgSets,
  configModule,
  moduleImports ? selection.defaultModuleImports,
  specialArgs ? { },
  ...
}:
let
  checkedPkgSets = assertPkgSets context pkgSets;
  registry = final.caisson-core.modules.nixos or { };
  # The framework module of the class: every registered `core`, forced.
  coreModules = selection.coreModules registry;
  selectedModules = moduleImports registry;
  pkgSetsModule =
    if nixpkgsModule then mkPkgSetsModule checkedPkgSets else mkBarePkgSetsModule checkedPkgSets;
in
{
  inherit checkedPkgSets;
  modules =
    coreModules
    ++ selectedModules
    ++ [
      configModule
      pkgSetsModule
    ];
  # Framework defaults first; the caller's win on conflict, as is
  # normal in the Nix ecosystem.
  specialArgs = {
    pkgSets = checkedPkgSets;
  }
  // specialArgs;
}
