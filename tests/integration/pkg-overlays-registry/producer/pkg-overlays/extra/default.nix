# SPDX-License-Identifier: MIT
#
# An entry no package set applies unless it selects it by name.
{ ... }:
{
  overlay = _final: _prev: {
    producerExtra = true;
  };
}
