# SPDX-License-Identifier: MIT
#
# The `default` darwin module caisson registers. A darwin configuration
# imports every registered module named `default` unless it passes
# `moduleImports`, so this is what a darwin configuration gets from
# caisson when it does not select its modules itself.
#
# It holds what a macOS machine does for the homes and the hjem
# configurations declared inside it:
#
# - `./caisson/forChildren.nix` gives each home the home-manager module
#   `darwin-parent`, and each hjem configuration the hjem module
#   `darwin-parent`. Both set the options that come from the machine.
# - The registered module `home-manager-activation` activates the homes
#   when the machine is activated.
# - The registered module `hjem-activation` writes the launchd agents
#   that apply the hjem configurations.
#
# The parts read options of caisson's core module. The core module
# leaves its options out when the library of the evaluation is not a
# caisson composition, so the parts are left out in the same case.
{ closure-lib, mkModule, ... }:
{ lib, ... }:
{
  imports =
    if lib ? caisson && lib ? caisson-core then
      [
        (mkModule ./caisson)
        closure-lib.caisson.modules.darwin.home-manager-activation
        closure-lib.caisson.modules.darwin.hjem-activation
        closure-lib.caisson.modules.darwin.activation-marker
      ]
    else
      [ ];
}
