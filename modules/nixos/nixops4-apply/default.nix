# SPDX-License-Identifier: MIT
#
# A NixOS module for a NixOS configuration that NixOps4 deploys. It
# imports the `apply` NixOS module of nixops4-nixos, which adds
# `bin/apply` to the toplevel: the script that sets the system profile
# and switches to the configuration. NixOps4 runs `bin/apply switch` on
# the host after it copies the toplevel there. Where nixpkgs declares
# `system.apply` itself, the module of nixops4-nixos adds nothing.
#
# The default module of the caisson-nixops4 class adds this module to
# the nearest NixOS configurations beneath a nixops4 configuration, its
# machines.
#
# The nixops4-nixos source is the one the composition declares or pins
# under the name `nixops4-nixos`, read from the library of the
# evaluation.
{ ... }:
{ lib, ... }:
let
  src =
    let
      found = lib.caisson-core.ecosystemSrc "nixops4-nixos";
    in
    if found == null then
      throw ''
        caisson's `nixops4-apply` NixOS module needs the nixops4-nixos source.
        Declare `defaultEcosystemSrc.nixops4-nixos` in the mkLib call, or pin a
        source named `nixops4-nixos` in the `sources` passed to mkLib.
      ''
    else
      found;
in
{
  _file = "caisson:nixops4-apply";
  imports = [ src.modules.nixos.apply ];
}
