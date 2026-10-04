# SPDX-License-Identifier: MIT
#
# The platforms a flake enumerates come from the composition: a tree
# declares `systems` on mkLib, and flake-parts' `systems` defaults to
# that list. A flake module may still set `systems` itself. A
# composition that declares none has no system in force, so the
# default is the empty list, and the flake has no per-system outputs.
{ config, lib, ... }:
{
  config.systems = lib.mkDefault (
    if config.caisson.manifest.systems == null then [ ] else config.caisson.manifest.systems
  );
}
