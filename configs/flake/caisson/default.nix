# SPDX-License-Identifier: MIT
#
# The flake top's configuration: the shared configuration of what
# caisson exports, evaluated beneath this top with its exports merged
# into this top's exports, plus the checks partition only a flake
# evaluation carries. Both the configuration and the evaluation come
# from the closure, the composition this configuration was registered
# in.
{ closure-inputs, closure-lib, ... }:
{ ... }:
let
  # A flake-parts evaluation holds no configurations beneath it, so
  # the shared configuration is finalized here, as a top is.
  impl = closure-lib.caisson-core.finalizeTop (
    closure-lib.caisson.structural.mkConfiguration {
      configModule = closure-lib.caisson-core.configs.structural.impl;
    }
  );
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
