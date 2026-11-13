# SPDX-License-Identifier: MIT
#
# The declaration of `caisson.importerNote`, which the module
# `importer` imports and defines.
{ lib, ... }:
{
  options.caisson.importerNote = lib.mkOption {
    type = lib.types.str;
    description = "A note that the module `importer` defines.";
  };
}
