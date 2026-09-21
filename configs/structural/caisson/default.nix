# SPDX-License-Identifier: MIT
#
# The structural top's configuration: the shared configuration of
# what caisson exports, evaluated beneath this top with its exports
# merged into this top's exports. Both the configuration and the
# evaluation come from the closure, the composition this
# configuration was registered in.
{ closure-lib, ... }:
{ ... }:
let
  impl = closure-lib.caisson.structural.mkConfiguration {
    configModule = closure-lib.caisson-core.configs.structural.impl;
  };
in
{
  caisson.exports = impl.outputs.exports;
}
