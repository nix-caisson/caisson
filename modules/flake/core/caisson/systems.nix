# SPDX-License-Identifier: MIT
#
# The platforms a flake enumerates come from the composition: a flake
# declares `systems` on mkLib, and flake-parts' `systems` defaults to
# that list. A flake module may still set `systems` itself. For a
# composition that declares no systems the default is the empty list,
# and the flake has no per-system outputs.
{ config, lib, ... }:
{
  config.systems = lib.mkDefault (
    if config.caisson.manifest.systems == null then [ ] else config.caisson.manifest.systems
  );
}
