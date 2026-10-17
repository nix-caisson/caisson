# SPDX-License-Identifier: MIT
#
# The `caisson.*` part of the default system-manager module.
{ closure-lib, ... }:
{ ... }:
{
  imports = [
    # `forChildren.nix` sets options under `caisson.forChildren`. The
    # core module declares those options.
    closure-lib.caisson.modules.systemManager.core
    (import ./forChildren.nix { inherit closure-lib; })
  ];
}
