# SPDX-License-Identifier: MIT
#
# The flake top's configuration: what caisson exports, from the
# structural configuration both tops share, plus the checks partition
# only a flake evaluation carries.
{ closure-inputs, ... }:
{ lib, ... }:
{

  imports = [
    # flake-parts' partitions module, from the flake-parts input of
    # this flake (a module file; it binds no library).
    closure-inputs.flake-parts.flakeModules.partitions
    ./partitions
    (lib.caisson.flake-parts.mkModule ../../structural/caisson)
  ];

  partitionedAttrs.checks = "checks";

  debug = false;

}
