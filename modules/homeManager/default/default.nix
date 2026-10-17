# SPDX-License-Identifier: MIT
#
# The `default` home-manager module caisson registers. A home imports
# every registered module named `default` unless it passes
# `moduleImports`, so this is what a home gets from caisson when it does
# not select its modules itself:
#
# - `activation-drift`, with which the activation of the home warns when
#   the home was built for a different version of the configuration it
#   is declared inside, such as its machine;
# - `activation-marker`, with which the activation of the home records
#   what it applied, for the configurations declared inside the home to
#   check in turn.
{ closure-lib, ... }:
{ ... }:
{
  imports = [
    closure-lib.caisson.modules.homeManager.activation-drift
    closure-lib.caisson.modules.homeManager.activation-marker
  ];
}
