# SPDX-License-Identifier: MIT
#
# A home-manager module that installs the Neovim of each nvf
# configuration declared inside the home, in `home.packages`. caisson's
# `default` home-manager module imports it. See
# `lib.caisson.nvf.packagesModule`.
{ closure-lib, ... }:
closure-lib.caisson.nvf.packagesModule [
  "home"
  "packages"
]
