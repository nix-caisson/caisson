# SPDX-License-Identifier: MIT
#
# The composition the nixos integration's entry points share: one
# definition of the module list and special arguments, so the variants
# cannot express different machines from the same arguments.
{ final }:
let
  selection = final.caisson.integrations;

  assertPkgSets =
    context: pkgSets:
    if pkgSets ? pkgs then pkgSets else throw "${context} requires `pkgSets.pkgs` to be defined.";

  # eval-config evaluations carry the nixpkgs module, so the package
  # set lands on `nixpkgs.pkgs`; the minimal evaluator has no such
  # module, so there it is the `pkgs` module argument instead.
  mkPkgSetsModule = pkgSets: {
    _file = "caisson-nixos:pkgSets";
    config = {
      nixpkgs.pkgs = pkgSets.pkgs;
    };
  };
  mkMinimalPkgSetsModule = pkgSets: {
    _file = "caisson-nixos:pkgSets-minimal";
    config = {
      _module.args.pkgs = final.mkDefault pkgSets.pkgs;
    };
  };
in
{
  context,
  minimal ? false,
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
    if minimal then mkMinimalPkgSetsModule checkedPkgSets else mkPkgSetsModule checkedPkgSets;
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
