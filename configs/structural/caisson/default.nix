# SPDX-License-Identifier: MIT
#
# The structural top's configuration: the shared configuration of
# what caisson exports, declared beneath this top under the name it
# is registered by (configs/structural/impl). What it exports is
# passed up into this top's exports.
{ ... }:
{ lib, ... }:
{
  caisson.structural.configurations.impl = lib.caisson.structural.mkConfiguration { };
}
