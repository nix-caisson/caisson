# SPDX-License-Identifier: MIT
#
# A system-manager module that installs the Neovim of each nvf
# configuration declared inside the system-manager configuration, in
# `environment.systemPackages`. caisson's `default` system-manager
# module imports it. See `lib.caisson.nvf.packagesModule`.
{ closure-lib, ... }:
closure-lib.caisson.nvf.packagesModule [
  "environment"
  "systemPackages"
]
