# SPDX-License-Identifier: MIT
#
# The system-manager test in a container of a distribution, run with
# system-manager's container test driver
# (`system-manager.lib.containerTest.makeContainerTest`). `distro`
# names a root filesystem of `container-distros.nix` beside this file.
# The driver installs Nix in the container with `nix-installer` when
# the container starts.
#
# The driver runs the container with systemd-nspawn in the build
# sandbox, which needs the `uid-range` system feature, so Nix must run
# with `auto-allocate-uids = true`. The test is therefore not among the
# checks `nix flake check` builds: it is the output
# `containerTests.x86_64-linux.system-manager-<distro>`, which CI builds
# with that setting, for each distribution.
{ inputs, distro }:
let
  sequence = import ./sequence.nix { inherit inputs; };
  inherit (sequence) pkgs;
in
inputs.system-manager.lib.containerTest.makeContainerTest {
  hostPkgs = pkgs;
  # The name of the container, which systemd-nspawn takes as a host
  # name, where `_` is not allowed.
  name = builtins.replaceStrings [ "_" ] [ "-" ] "caisson-system-manager-${distro}";
  rootfs = (import ./container-distros.nix { inherit inputs pkgs; }).${distro};
  toplevel = sequence.v1;
  extraPathsToRegister = [
    sequence.v2
    sequence.carolV1
    sequence.carolV2
  ];
  testScript = ''
    # The driver's `execute` returns a `subprocess.CompletedProcess`.
    def exit_status(command):
        return machine.execute(command).returncode

    def activate(toplevel):
        logs = machine.activate(profile=toplevel)
        for line in logs.split("\n"):
            assert "ERROR" not in line, line
        machine.wait_for_unit("system-manager.target")

    start_all()
    machine.wait_for_unit("multi-user.target")

  ''
  + sequence.script;
}
