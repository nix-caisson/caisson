# SPDX-License-Identifier: MIT
#
# The package-set flake module. Consumers also need caisson's default
# flake module (configInfo and the export options) applied, which any
# caisson composition selects from its own registry.
{
  closure-self-modules,
  mkModule,
  ...
}:
{ ... }:
{
  imports = [
    closure-self-modules.nixpkgs-interface
    (mkModule ./caisson)
  ];
}
