# SPDX-License-Identifier: MIT
#
# An entry two importers share: it counts how often it is applied, so a
# package set that reaches it through two imports shows it applied once.
{ ... }:
{
  overlay = _final: prev: {
    sharedApplied = (prev.sharedApplied or 0) + 1;
  };
}
