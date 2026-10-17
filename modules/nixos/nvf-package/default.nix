# SPDX-License-Identifier: MIT
#
# A NixOS module that installs the Neovim of each nvf configuration
# declared inside the NixOS configuration, in
# `environment.systemPackages`. caisson's `default` NixOS module imports
# it. See `lib.caisson.nvf.packagesModule`.
{ closure-lib, ... }:
closure-lib.caisson.nvf.packagesModule [
  "environment"
  "systemPackages"
]
