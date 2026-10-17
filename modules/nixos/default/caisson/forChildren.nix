# SPDX-License-Identifier: MIT
#
# What a NixOS configuration gives the homes declared inside it.
#
# A configuration gives things to the configurations declared inside
# it through the options under `caisson.forChildren`. This file adds
# the home-manager module `nixos-parent` to the modules that a home
# declared inside this NixOS configuration imports by default, and the
# hjem module `nixos-parent` to those of a hjem configuration declared
# inside it.
#
# `nixos-parent` is the module caisson registers as
# `modules/homeManager/nixos-parent`. It sets the options of a home
# that come from its machine: the home directory and the user ID of
# the account, and the Nix of the machine. home-manager has a NixOS
# module that sets the same options in the homes it embeds, and
# caisson does not use that NixOS module.
#
# There are two ways to take this out. A NixOS configuration that
# passes `moduleImports` selects its modules itself, and then no home
# inside it gets `nixos-parent` from here. A home that passes
# `moduleImports` selects its modules itself, and then that home does
# not get it.
#
# `closure-lib` is the library of caisson, where `nixos-parent` is
# registered under that name.
{ closure-lib }:
{ ... }:
{
  caisson.forChildren.extraDefaultModuleImports.homeManager = _lib: [
    closure-lib.caisson.modules.homeManager.nixos-parent
  ];

  # The hjem module `nixos-parent` sets the home directory of a hjem
  # configuration declared inside this machine from the account of its
  # user, and refuses a user the machine has no account for.
  caisson.forChildren.extraDefaultModuleImports.hjem = _lib: [
    closure-lib.caisson.modules.hjem.nixos-parent
  ];
}
