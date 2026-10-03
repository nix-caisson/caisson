# SPDX-License-Identifier: MIT
#
# The package-set flake module: hands perSystem the sets of the
# package configs declared in mkLib's `pkgSets`, and exports the
# package overlay registry and, when enabled, a set and its scope.
{ mkModule, ... }:
{ ... }:
{
  imports = [
    (mkModule ./caisson)
  ];
}
