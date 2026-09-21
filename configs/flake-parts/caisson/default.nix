# SPDX-License-Identifier: MIT
#
# The flake top's configuration: the structural configuration of
# caisson evaluated beneath this flake top, its exports merged into
# this top's exports (what a child configuration will be once
# children exist), plus the checks partition only a flake evaluation
# carries.
{ closure-inputs, ... }:
{ lib, ... }:
let
  structural = lib.caisson.structural.mkConfiguration {
    configModule = ../../structural/caisson;
  };
in
{

  imports = [
    # flake-parts' partitions module, from the flake-parts input of
    # this flake (a module file; it binds no library).
    closure-inputs.flake-parts.flakeModules.partitions
    ./partitions
  ];

  partitionedAttrs.checks = "checks";

  debug = false;

  caisson.exports = structural.outputs.exports;

}
