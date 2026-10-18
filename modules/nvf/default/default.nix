# SPDX-License-Identifier: MIT
#
# The `default` module caisson registers for the `nvf` class, and, for
# the same file, for the `nixvim` class. A configuration of either
# class imports every registered module named `default` unless it
# passes `moduleImports`.
#
# It declares `caisson.drift.warn`. The configuration is kept in a Nix
# profile of its own, and its `activate` checks for drift against the
# configuration it is declared inside, as a home does
# (`lib.caisson.integrations.profileOf`). The option turns the warning
# off.
{ ... }:
{ lib, ... }:
{
  options.caisson.drift.warn = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Whether `activate` of this configuration prints a warning when the
      configuration was built for a version of the configuration it is
      declared inside, such as a home or a machine, that differs from
      the version that is applied.
    '';
  };
}
