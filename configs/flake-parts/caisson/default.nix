# SPDX-License-Identifier: MIT
#
# The flake top's configuration: the shared configuration of what
# caisson exports, evaluated beneath this top with its exports merged
# into this top's exports, plus the checks partition only a flake
# evaluation carries.
{ closure-inputs, ... }:
{ lib, ... }:
let
  impl = lib.caisson.structural.mkConfiguration {
    configModule = lib.caisson-core.configs.structural.impl;
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

  caisson.exports = impl.outputs.exports;

}
