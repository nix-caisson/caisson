# SPDX-License-Identifier: MIT
#
# A local entry the export selector leaves out.
{ ... }:
{
  overlay = _final: _prev: {
    internalOnly = true;
  };
}
