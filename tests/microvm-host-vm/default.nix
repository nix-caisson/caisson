# SPDX-License-Identifier: MIT
#
# A NixOS test of a guest of a caisson-microvm configuration that a
# host runs through caisson's NixOS module `microvm-host` and the units
# of microvm.nix's host module, in a VM that runs the guest on nested
# KVM. `inputs` is the dependency pool of the checks partition with
# `caisson` set to the tree itself.
#
# The test host holds the caisson-microvm configuration `pool`,
# registered as `configs/caisson-microvm/pool` here. Its one guest is
# `probe`, the NixOS configuration registered as `configs/nixos/probe`
# here. `probe` runs on cloud-hypervisor with the vsock CID 10 and
# answers on its vsock port 5000 with what it reads there.
#
# The test starts the unit `microvm@probe.service` and checks that the
# unit is active. As root, it then connects to the Unix socket of the
# hybrid vsock of the guest, `/var/lib/microvms/probe/notify.vsock`,
# sends `CONNECT 5000`, reads `OK`, and gets back a line it sends.
#
# The NixOS test framework evaluates its nodes itself, with the
# `eval-config.nix` of nixpkgs, and a node is a NixOS module. The node
# here is evaluated on the library of a caisson evaluation of the same
# host, passed through `node.specialArgs`, so the modules of caisson
# find `lib.caisson` and the manifest of the host. The node imports
# what caisson's NixOS evaluator imports from the registry: the
# framework modules of the class and the modules the host selects.
{ inputs }:
let
  core = inputs.caisson.lib.caisson-core;

  system = "x86_64-linux";

  pkgs = import inputs.nixpkgs { inherit system; };

  lib = core.mkLib {
    name = "microvm-host-vm";
    sources = {
      inherit (inputs) nixpkgs microvm;
    };
    systems = [ system ];
    projects.caisson = inputs.caisson;
    defaultEcosystemSrc = sources: {
      nixpkgs-lib = sources.nixpkgs;
      nixos = sources.nixpkgs;
    };
    configs = lib: lib.caisson-core.mkModules ./configs;
    pkgSets = _lib: {
      default =
        { name, parent }:
        {
          _type = "caisson-manifest";
          type = "nixpkgs";
          inherit name parent;
          children.nixpkgs.${system} = {
            _type = "caisson-manifest";
            type = "nixpkgs";
            name = system;
            value = pkgs;
          };
        };
    };
  };

  # What the test host declares, in the caisson evaluation and in the
  # node: the caisson-microvm configuration `pool`.
  host =
    { lib, ... }:
    {
      key = "caisson:tests/microvm-host-vm:host";

      caisson.caisson-microvm.configurations.pool = lib.caisson.caisson-microvm.mkConfiguration { };
    };

  # The caisson evaluation of the test host. A module of the evaluation
  # hands its library out through an option.
  hostTop = lib.caisson.nixos.mkTopConfiguration {
    moduleImports = modules: [
      modules."caisson/default"
      modules."caisson/microvm-host"
    ];
    configModule =
      { lib, ... }:
      {
        key = "caisson:tests/microvm-host-vm:top";
        imports = [ host ];
        options.microvmHostVmLib = lib.mkOption { type = lib.types.raw; };
        config = {
          microvmHostVmLib = lib;
          boot.loader.grub.enable = false;
          fileSystems."/" = {
            device = "none";
            fsType = "tmpfs";
          };
          system.stateVersion = "25.05";
        };
      };
  };
  hostConfig = (hostTop.config or hostTop.${system}.config);
  hostLib = hostConfig.microvmHostVmLib;

  registry = hostLib.caisson.modules.nixos;

  # Connects to the socket of the hybrid vsock of the guest, asks for
  # its vsock port 5000, and prints the line the guest sends back for
  # the line `hello`.
  ask = pkgs.writeShellScript "microvm-host-vm-ask" ''
    coproc guest { exec ${pkgs.lib.getExe pkgs.socat} - UNIX-CONNECT:/var/lib/microvms/probe/notify.vsock; }
    echo "CONNECT 5000" >&"''${guest[1]}"
    read -r -t 30 answer <&"''${guest[0]}" || exit 1
    case "$answer" in
      "OK "*) ;;
      *)
        echo "the socket answered: $answer" >&2
        exit 1
        ;;
    esac
    echo hello >&"''${guest[1]}"
    read -r -t 30 line <&"''${guest[0]}" || exit 1
    kill "$guest_PID"
    echo "$line"
  '';
in
pkgs.testers.runNixOSTest {
  name = "caisson-microvm-host-vm";

  node.specialArgs.lib = hostLib;

  # The test host runs on KVM, so its guest runs on nested KVM.
  qemu.forceAccel = true;

  nodes.host = {
    imports = hostLib.caisson.integrations.frameworkModules "nixos" registry ++ [
      registry."caisson/default"
      registry."caisson/microvm-host"
      host
    ];
    system.stateVersion = "25.05";
    # caisson's `default` module names the machine after the
    # composition, `microvm-host-vm`. The test framework names the node
    # `host`, and the node keeps that name.
    networking.hostName = pkgs.lib.mkForce "host";

    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;
    # The virtualization extensions of the CPU of the machine that runs
    # the test, which cloud-hypervisor uses through `/dev/kvm`.
    virtualisation.qemu.options = [
      "-cpu"
      "host"
    ];
    boot.kernelModules = [
      "kvm-amd"
      "kvm-intel"
    ];
  };

  testScript = ''
    from datetime import timedelta

    host.wait_for_unit("multi-user.target")
    host.succeed("test -c /dev/kvm")

    host.succeed("systemctl start microvm@probe.service")
    host.succeed("systemctl is-active microvm@probe.service")
    host.wait_until_succeeds("${ask} | grep -qx hello", timeout=timedelta(minutes=5))
  '';
}
