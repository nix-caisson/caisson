# SPDX-License-Identifier: MIT
#
# The entry the export selector publishes.
{ ... }:
{
  overlay = _final: _prev: {
    exportedPolyfill = "ok";
  };
}
