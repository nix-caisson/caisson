# SPDX-License-Identifier: MIT
#
# A darwin module that installs the Neovim of each nvf configuration
# declared inside the darwin configuration, in
# `environment.systemPackages`. caisson's `default` darwin module
# imports it. See `lib.caisson.nvf.packagesModule`.
{ closure-lib, ... }:
closure-lib.caisson.nvf.packagesModule [
  "environment"
  "systemPackages"
]
