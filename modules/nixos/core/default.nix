# SPDX-License-Identifier: MIT
#
# The core module of the nixos class. caisson puts it in every NixOS
# configuration that the nixos and nixos-minimal integrations
# evaluate. It is caisson's core module, which is the same for every
# class (the `generic` registry entry, reached through the closure),
# plus what a NixOS configuration gives the homes declared inside it.
#
# The second part is left out when the library of the evaluation is
# not a caisson composition. The generic core module leaves its options
# out in the same case, and the second part defines into those
# options.
{ closure-lib, ... }:
{ lib, ... }:
{
  imports = [
    closure-lib.caisson-core.modules.generic.core
  ]
  ++ (if lib ? caisson && lib ? caisson-core then [ ./caisson ] else [ ]);
}
