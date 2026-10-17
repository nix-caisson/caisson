# SPDX-License-Identifier: MIT
#
# The `default` home-manager module caisson registers. A home imports
# every registered module named `default` unless it passes
# `moduleImports`, so this is what a home gets from caisson when it does
# not select its modules itself: the module `nvf-package`, which installs
# the Neovim of each nvf configuration declared inside the home.
{ closure-lib, ... }:
{ ... }:
{
  imports = [ closure-lib.caisson.modules.homeManager.nvf-package ];
}
