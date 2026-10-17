# SPDX-License-Identifier: MIT
#
# The `caisson.*` part of the default darwin module.
{ closure-lib, ... }:
{ ... }:
{
  imports = [
    # `forChildren.nix` sets options under `caisson.forChildren`. The
    # core module declares those options.
    closure-lib.caisson.modules.darwin.core
    (import ./forChildren.nix { inherit closure-lib; })
  ];
}
