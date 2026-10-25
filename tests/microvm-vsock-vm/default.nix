# SPDX-License-Identifier: MIT
#
# A NixOS test of the hybrid vsock of a cloud-hypervisor guest started
# through caisson's NixOS module `microvm-host`, run in a VM that runs
# the guest on nested KVM. `inputs` is the dependency pool of the
# checks partition with `caisson` set to the tree itself.
#
# The test host holds the caisson-microvm configuration `pool`, whose
# guests run on cloud-hypervisor. Its one slot of the kind `echo` is the
# guest `echo-1`, the NixOS configuration registered as
# `configs/nixos/echo` here, which answers on its vsock port 5000 with
# what it reads there. The user `alice` operates `echo-1`, and the user
# `bob` operates no guest.
#
# The test starts the guest and checks that the working directory of
# the guest and the socket that `vsockSocket` of its slot records belong
# to the group `microvm-echo-1`, with the modes 0750 and 0660. `alice`
# connects to the socket, sends `CONNECT 5000`, reads `OK`, and gets
# back a line she sends. `bob` cannot connect to the socket. The test
# stops the guest, starts it again, and checks the same of the socket of
# the new run. It stops and starts the unit with two commands, because
# with the microvm.nix the tests pin, `systemctl restart` of a
# cloud-hypervisor guest that has a vsock CID times out: the guest boots,
# and its unit never gets the notification that the guest is ready.
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
    name = "microvm-vsock-vm";
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
  # node: the guests and the users.
  host =
    { lib, ... }:
    {
      key = "caisson:tests/microvm-vsock-vm:host";

      caisson.caisson-microvm.configurations.pool = lib.caisson.caisson-microvm.mkConfiguration {
        configModule = {
          hypervisor = "cloud-hypervisor";
          vcpu = 1;
          mem = 512;
          slots.echo = {
            count = 1;
            cidBase = 10;
            vsockPort = 5000;
          };
        };
      };
      caisson.microvm-host.operators.alice = [ "echo-1" ];

      users.users.alice.isNormalUser = true;
      users.users.bob.isNormalUser = true;
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
        key = "caisson:tests/microvm-vsock-vm:top";
        imports = [ host ];
        options.microvmVsockVmLib = lib.mkOption { type = lib.types.raw; };
        config = {
          microvmVsockVmLib = lib;
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
  hostLib = hostConfig.microvmVsockVmLib;

  registry = hostLib.caisson.modules.nixos;

  # The slot of the guest, as the caisson-microvm configuration records
  # it.
  slot = hostConfig.caisson.caisson-microvm.configurations.pool.outputs.slots.echo-1;
  socket = slot.vsockSocket;
  port = toString slot.vsockPort;

  # Connects to the socket of the guest, asks for its vsock port, and
  # prints the line the guest sends back for the line `hello`.
  ask = pkgs.writeShellScript "microvm-vsock-vm-ask" ''
    coproc guest { exec ${pkgs.lib.getExe pkgs.socat} - UNIX-CONNECT:${socket}; }
    echo "CONNECT ${port}" >&"''${guest[1]}"
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
  name = "caisson-microvm-vsock-vm";

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
    # composition, `microvm-vsock-vm`. The test framework names the node
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

    environment.systemPackages = [ pkgs.socat ];
  };

  testScript = ''
    from datetime import timedelta

    unit = "microvm@echo-1.service"
    socket = "${socket}"

    def as_user(user, command):
        return f"runuser -u {user} -- {command}"

    def check_access():
        directory = host.succeed(f"stat -c '%U %G %a' $(dirname {socket})").strip()
        assert directory == "microvm microvm-echo-1 750", f"the working directory is {directory}"
        mode = host.succeed(f"stat -c '%U %G %a' {socket}").strip()
        assert mode == "microvm microvm-echo-1 660", f"the socket is {mode}"
        host.wait_until_succeeds(
            as_user("alice", "${ask}") + " | grep -qx hello", timeout=timedelta(minutes=5)
        )
        host.fail(as_user("bob", f"socat -u /dev/null UNIX-CONNECT:{socket}"))

    host.wait_for_unit("multi-user.target")
    host.succeed("test -c /dev/kvm")

    host.succeed(f"systemctl start {unit}")
    check_access()

    host.succeed(f"systemctl stop {unit}")
    host.succeed(f"systemctl start {unit}")
    check_access()
  '';
}
