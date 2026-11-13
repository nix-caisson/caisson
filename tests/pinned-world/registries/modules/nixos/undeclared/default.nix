# SPDX-License-Identifier: MIT
#
# A NixOS module that defines an option under `caisson` and imports
# nothing. The check `registries` of a caisson top whose NixOS
# configuration selects this module fails, because a NixOS
# configuration evaluated outside caisson has no module that declares
# `caisson.structural.exportNote`. The check `registriesRefusesAnEntryWithoutItsDeclaration`
# of the pinned-world suite reads that failure.
{ ... }:
{ ... }:
{
  caisson.structural.exportNote = "a note of the undeclared module";
}
