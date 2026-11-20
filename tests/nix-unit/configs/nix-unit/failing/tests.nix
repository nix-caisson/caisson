# SPDX-License-Identifier: MIT
#
# A passing case and a failing case.
{ lib, ... }:
{
  testPasses = {
    expr = lib.add 1 1;
    expected = 2;
  };
  testFailsOnPurpose = {
    expr = lib.add 1 1;
    expected = 3;
  };
}
