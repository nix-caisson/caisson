# SPDX-License-Identifier: MIT
#
# An hjem module that installs the Neovim of each nvf configuration
# declared inside the hjem configuration, in `packages`. caisson's
# `default` hjem module imports it. See `lib.caisson.nvf.packagesModule`.
{ closure-lib, ... }:
closure-lib.caisson.nvf.packagesModule [ "packages" ]
