# SPDX-License-Identifier: MIT
#
# Cases over what the file of a nix-unit configuration receives in the
# build sandbox: the library composed again there, its manifest, and
# the dependencies of the configuration.
{
  lib,
  manifest,
  dependencies,
}:
{
  testTheLibraryCarriesTheIntegrations = {
    expr = lib.caisson ? nix-unit && lib.caisson ? flake-parts;
    expected = true;
  };
  testTheLibraryHoldsTheRegisteredConfigurations = {
    expr = builtins.attrNames lib.caisson.configs.nixUnit;
    expected = [
      "failing"
      "passing"
    ];
  };
  testTheManifestNamesTheProject = {
    expr = manifest.name;
    expected = "nix-unit";
  };
  testADependencyIsTheFlakeItPins = {
    expr = dependencies.nixpkgs.lib.trivial.release == lib.trivial.release;
    expected = true;
  };
}
