# SPDX-License-Identifier: MIT
#
# The platforms a flake enumerates come from the composition: a tree
# declares `systems` once, on mkLib, and flake-parts' `systems`
# defaults to that list. A flake module may still set `systems`
# itself, and a composition that declares none leaves the option as
# flake-parts leaves it.
{ config, lib, ... }:
{
  config.systems = lib.mkIf (config.caisson.manifest.systems != null) (
    lib.mkDefault config.caisson.manifest.systems
  );
}
