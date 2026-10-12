# SPDX-License-Identifier: MIT
#
# The flake top's configuration: the shared configuration of what
# caisson exports, declared beneath this top under the name it is
# registered by (configs/structural/impl), plus the checks partition
# only a flake evaluation carries. What the shared configuration
# exports is passed up into this top's exports, and from there into
# the flake outputs.
{ closure-inputs, ... }:
{ lib, ... }:
{

  imports = [
    # flake-parts' partitions module, from the flake-parts input of
    # this flake (a module file; it binds no library).
    closure-inputs.flake-parts.flakeModules.partitions
    ./partitions
  ];

  partitionedAttrs.checks = "checks";

  debug = false;

  caisson.structural.configurations.impl = lib.caisson.structural.mkConfiguration { };

  # Each module that caisson exports reads the options under `caisson`
  # or the library under `lib.caisson`, so it works only inside an
  # evaluation that caisson makes. A flake that lists caisson in
  # `projects` gets these modules from the manifest. None of them is
  # published in the `modules` flake output.
  caisson.flakeOutputs.modules = _: { };

}
