# SPDX-License-Identifier: MIT
#
# The host name of a NixOS configuration defaults to the name the
# configuration is declared under, so the NixOS configuration declared
# as `nas-1` names the computer it runs on `nas-1`. The default is at
# `mkDefault` priority, so a definition of `networking.hostName` in a
# module of the NixOS configuration replaces it. A NixOS configuration
# with no name, a top of a composition that declares none on mkLib,
# keeps NixOS's default. A NixOS configuration evaluated without
# NixOS's networking module, such as by the minimal NixOS evaluator,
# has no host name to set.
{ ... }:
{ lib, options, ... }:
let
  name = lib.caisson-core.evalManifest.name or null;
in
{
  config = lib.optionalAttrs (name != null && options ? networking.hostName) {
    networking.hostName = lib.mkDefault name;
  };
}
