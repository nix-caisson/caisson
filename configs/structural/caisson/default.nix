# SPDX-License-Identifier: MIT
#
# The structural top's configuration: the shared configuration of
# what caisson exports, evaluated beneath this top with its exports
# merged into this top's exports.
{ ... }:
{ lib, ... }:
let
  impl = lib.caisson.structural.mkConfiguration {
    configModule = lib.caisson-core.configs.structural.impl;
  };
in
{
  caisson.exports = impl.outputs.exports;
}
