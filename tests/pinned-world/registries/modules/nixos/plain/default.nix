# SPDX-License-Identifier: MIT
#
# A NixOS module that defines no option under `caisson`. The check
# `registriesIgnoresTheFileThatImportsAnEntry` of the pinned-world
# suite imports it from a configuration module that defines an option
# under `caisson`, and the check `registries` passes.
{ ... }:
{ ... }:
{
  environment.etc."pinned-world/plain".text = "plain";
}
