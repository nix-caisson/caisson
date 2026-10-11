# SPDX-License-Identifier: MIT
#
# The `caisson.*` part of the default NixOS module.
{ closure-lib, ... }:
{ ... }:
{
  imports = [
    # `forChildren.nix` sets an option under `caisson.forChildren`.
    # The core module declares those options.
    closure-lib.caisson-core.modules.nixos.core
    (import ./forChildren.nix { inherit closure-lib; })
  ];
}
