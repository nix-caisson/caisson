# SPDX-License-Identifier: MIT
#
# The configuration of the structural caisson top: the shared
# configuration of what caisson exports, declared inside this caisson
# top under the name it is registered by (configs/structural/impl).
# What it exports is passed up into the exports of this caisson top.
{ ... }:
{ lib, ... }:
{
  caisson.structural.configurations.impl = lib.caisson.structural.mkConfiguration { };
}
