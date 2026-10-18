# SPDX-License-Identifier: MIT
#
# What a darwin configuration gives the homes and the hjem
# configurations declared inside it.
#
# A configuration gives things to the configurations declared inside
# it through the options under `caisson.forChildren`. This file adds
# the home-manager module `darwin-parent` to the modules that a home
# declared inside this darwin configuration imports by default, and
# the hjem module `darwin-parent` to those of a hjem configuration
# declared inside it. Each sets the options that come from the machine:
# the home directory from the account of the user, and for a home the
# user ID and the Nix of the machine.
#
# A darwin configuration that passes `moduleImports` selects its
# modules itself, and then nothing inside it gets these modules from
# here. A home or hjem configuration that passes `moduleImports`
# selects its modules itself, and gets the module only if it lists it.
#
# `closure-lib` is the library of caisson, where the modules are
# registered.
{ closure-lib }:
{ ... }:
{
  caisson.forChildren.extraDefaultModuleImports.homeManager = _lib: [
    closure-lib.caisson.modules.homeManager.darwin-parent
  ];

  caisson.forChildren.extraDefaultModuleImports.hjem = _lib: [
    closure-lib.caisson.modules.hjem.darwin-parent
  ];
}
