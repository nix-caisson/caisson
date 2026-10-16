# SPDX-License-Identifier: MIT
#
# The default module of the disko class.
#
# The NixOS configurations declared inside a disko configuration are
# installed onto its layout. This module adds caisson's NixOS module
# `disko-layout`, which imports disko's NixOS module and defines
# `disko.devices` from the layout, to the modules that a NixOS
# configuration declared inside this disko configuration imports by
# default. A NixOS configuration that passes `moduleImports` selects
# its modules itself, and then it lists `disko-layout` itself, as
# `caisson/disko-layout` in a flake that lists caisson in `projects`.
#
# The NixOS configuration declared as `default` is passed up under the
# name of the disko configuration, so the machine installed onto the
# layout `nas-1` is published as `nixosConfigurations.nas-1`, beside
# `diskoConfigurations.nas-1`. A disko configuration that sets
# `caisson.nixos.exported` passes its NixOS configurations up its own
# way.
#
# `closure-lib` is the library of caisson, where `disko-layout` is
# registered under that name.
{ closure-lib, ... }:
{ lib, ... }:
{
  # The options under `caisson` are declared by the core module of the
  # class.
  imports = [ closure-lib.caisson.modules.disko.core ];

  caisson.forChildren.extraDefaultModuleImports.nixos = _lib: [
    closure-lib.caisson.modules.nixos.disko-layout
  ];

  caisson.nixos.exported = lib.mkDefault (
    lib.caisson.integrations.renameDefault lib.caisson-core.evalManifest.name
  );
}
