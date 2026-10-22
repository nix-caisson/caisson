# SPDX-License-Identifier: MIT
#
# Marks two functions of the composed lib: `getExe`, of the package-set
# library `meta`, and `splitString`, a general utility. The checks read
# which of the two a package set's lib still carries.
{ ... }:
{
  overlay = _final: _prev: {
    getExe = _: "marked by the composition";
    splitString = _: _: [ "marked by the composition" ];
  };
}
