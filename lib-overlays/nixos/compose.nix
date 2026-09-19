# SPDX-License-Identifier: MIT
#
# The composition the nixos integration's entry points share: one
# definition of the module list and special arguments, so the variants
# cannot express different machines from the same arguments.
{ final }:
let
  assertPkgSets =
    context: pkgSets:
    if pkgSets ? pkgs then pkgSets else throw "${context} requires `pkgSets.pkgs` to be defined.";

  # eval-config evaluations carry the nixpkgs module, so the package
  # set lands on `nixpkgs.pkgs`; the minimal evaluator has no such
  # module, so there it is the `pkgs` module argument instead.
  mkFrameworkModule = pkgSets: {
    _file = "caisson-nixos:framework";
    config = {
      nixpkgs.pkgs = pkgSets.pkgs;
    };
  };
  mkMinimalFrameworkModule = pkgSets: {
    _file = "caisson-nixos:framework-minimal";
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
  moduleImports ? builtins.attrValues,
  specialArgs ? { },
  ...
}:
let
  checkedPkgSets = assertPkgSets context pkgSets;
  selectedModules = moduleImports (final.caisson-core.modules.nixos or { });
  frameworkModule =
    if minimal then mkMinimalFrameworkModule checkedPkgSets else mkFrameworkModule checkedPkgSets;
in
{
  inherit checkedPkgSets;
  modules = selectedModules ++ [
    configModule
    frameworkModule
  ];
  # Framework defaults first; the caller's win on conflict, as is
  # normal in the Nix ecosystem.
  specialArgs = {
    pkgSets = checkedPkgSets;
  }
  // specialArgs;
}
