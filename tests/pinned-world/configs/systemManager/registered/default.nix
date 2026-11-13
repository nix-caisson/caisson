# SPDX-License-Identifier: MIT
#
# A system-manager configuration of the registered world.
#
# The registered world declares a NixOS configuration and a
# system-manager configuration under the same name, `registered`. The
# nixos and system-manager integrations both declare the check
# `toplevel`, so both checks would be published as
# `registered-toplevel`, and the caisson top refuses checks that share a
# published name. This configuration turns its check off.
{ ... }:
{ ... }:
{
  environment.etc."registered".text = "registered";
  caisson.checks.toplevel.enable = false;
}
