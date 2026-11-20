# SPDX-License-Identifier: MIT
#
# A NixOS test of the registered world, with the node `machine`.
{ ... }:
{ ... }:
{
  nodes.machine = { };
  testScript = ''
    machine.wait_for_unit("multi-user.target")
  '';
}
