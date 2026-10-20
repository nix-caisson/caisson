# SPDX-License-Identifier: MIT
#
# The system-manager test in a QEMU VM of a distribution, run with
# numtide's nix-vm-test. `distro` is the name of the distribution and
# its version joined by `-`, as nix-vm-test names them, such as
# `ubuntu-22_04`.
#
# The VM boots the cloud image the distribution publishes, with the
# kernel and the systemd of the distribution. nix-vm-test adds a unit
# that gives the test driver a shell, masks the SSH server, configures
# the network with DHCP, and mounts the Nix store of the host at
# `/nix/.ro-store` with an overlay on `/nix/store`.
#
# The test installs Nix as a host of system-manager has it, with `nix-installer`, in the version
# system-manager's container test driver installs in a container.
# `nix-installer` renames what it unpacks into `/nix/store`, which
# fails across filesystems, so the test first unmounts the overlay. It
# then copies the closure of the test from `/nix/.ro-store` into the
# store of the VM and registers it in the Nix database.
{ inputs, distro }:
let
  sequence = import ./sequence.nix { inherit inputs; };
  inherit (sequence) pkgs;

  parts = pkgs.lib.splitString "-" distro;

  installer = pkgs.fetchurl {
    url = "https://github.com/NixOS/nix-installer/releases/download/2.35.2/nix-installer-x86_64-linux";
    sha256 = "1k3ajkhihx5xr0yrz193isiync9pmzxxwrb3sfs5r55df36s2j2l";
  };

  closure = pkgs.closureInfo {
    rootPaths = [
      sequence.v1
      sequence.v2
      sequence.carolV1
      sequence.carolV2
    ];
  };

  test = inputs.nix-vm-test.lib.x86_64-linux.${builtins.head parts}.${pkgs.lib.last parts} {
    sharedDirs = { };
    memorySize = 2048;
    diskSize = "+6G";
    testScript = ''
      import datetime

      machine = vm

      def exit_status(command):
          return machine.execute(command)[0]

      def activate(toplevel):
          logs = machine.succeed(f"RUST_LOG=debug {toplevel}/bin/activate 2>&1")
          for line in logs.split("\n"):
              assert "ERROR" not in line, line
          machine.wait_for_unit("system-manager.target")

      start_all()
      machine.wait_for_unit("multi-user.target")
      # The test grows the root partition onto the larger disk with the
      # `growpart` of the cloud image. nix-vm-test's unit for that
      # starts with `apt-get install`, which fails in the VM. An exit
      # status of 1 from `growpart` means that the partition already
      # fills the disk.
      machine.succeed(
          "growpart /dev/sda 1 || test $? -eq 1",
          "resize2fs /dev/sda1",
      )
      machine.succeed(
          "install -m755 ${installer} /usr/local/bin/nix-installer",
          "cp ${closure}/store-paths ${closure}/registration /root/",
          "umount /nix/store /nix/.rw-store",
      )
      machine.succeed(
          "/usr/local/bin/nix-installer install linux --no-confirm --extra-conf 'sandbox = false'",
          timeout=datetime.timedelta(minutes=5),
      )
      machine.wait_for_unit("nix-daemon.socket")
      machine.succeed(
          "while read -r path; do"
          " test -e $path || cp -a /nix/.ro-store/''${path#/nix/store/} /nix/store/;"
          " done < /root/store-paths",
          timeout=datetime.timedelta(minutes=10),
      )
      machine.succeed("/nix/var/nix/profiles/default/bin/nix-store --load-db < /root/registration")
      print(machine.succeed("df -h /"))

    ''
    + sequence.script;
  };
in
test.sandboxed
