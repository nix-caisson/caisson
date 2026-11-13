# SPDX-License-Identifier: MIT
#
# The NixOS test `smoke`, declared inside the NixOS configuration
# `nas-1`. The node `machine` writes the host name of `nas-1` to
# /etc/parent-host-name, and the test script checks the file in the VM.
# The host name comes from the result of the childless evaluation of
# `nas-1`, which the manifest of the test holds as `nearest.nixos`.
{ ... }:
{ lib, ... }:
let
  parent = lib.caisson-core.evalManifest.nearest.nixos.value.config;
in
{
  nodes.machine = {
    environment.etc."parent-host-name".text = parent.networking.hostName;
  };
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    name = machine.succeed("cat /etc/parent-host-name").strip()
    assert name == "nas-one", f"the node read the host name {name!r}"
  '';
}
