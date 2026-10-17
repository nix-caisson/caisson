# SPDX-License-Identifier: MIT
#
# The `default` hjem module caisson registers. An hjem configuration
# imports every registered module named `default` unless it passes
# `moduleImports`, so this is what it gets from caisson when it does not
# select its modules itself: the module `nvf-package`, which installs
# the Neovim of each nvf configuration declared inside it.
{ closure-lib, ... }:
{ ... }:
{
  imports = [ closure-lib.caisson.modules.hjem.nvf-package ];
}
