# SPDX-License-Identifier: MIT
#
# A stand-in for `nixos/modules/module-list.nix` of a nixpkgs source
# tree: the base module list `nixos/lib/eval-config.nix` defaults to
# and `lib.caisson.nixos.mkConfigurationFull` passes explicitly. The
# real list is the NixOS module tree, which is where `nixpkgs.pkgs`
# and the rest of the NixOS options are declared; this list declares
# `nixpkgs.pkgs`, so an evaluation carrying NixOS' nixpkgs module has
# the option that module defines, and an option a configuration reads
# to show the list reached the evaluation. It also declares the
# options of a machine that a home declared inside it is given: the
# accounts under `users.users`, and the Nix the machine runs.
[
  (
    { config, lib, ... }:
    {
      options = {
        nixpkgs.pkgs = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };
        users.users = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                home = lib.mkOption {
                  type = lib.types.str;
                };
                uid = lib.mkOption {
                  type = lib.types.nullOr lib.types.int;
                  default = null;
                };
              };
            }
          );
          default = { };
        };
        nix.enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
        nix.package = lib.mkOption {
          type = lib.types.str;
          default = "nix-of-the-machine";
        };
        # The options a machine defines to activate the homes
        # declared inside it: the systemd units, and the assertions
        # NixOS checks before it builds a system.
        systemd.services = lib.mkOption {
          type = lib.types.attrsOf lib.types.raw;
          default = { };
        };
        systemd.user.services = lib.mkOption {
          type = lib.types.attrsOf lib.types.raw;
          default = { };
        };
        assertions = lib.mkOption {
          type = lib.types.listOf lib.types.raw;
          default = [ ];
        };
        # The files a machine installs under `/etc`. A machine with
        # homes declared inside it writes a record of which NixOS
        # configuration it runs there.
        environment.etc = lib.mkOption {
          type = lib.types.attrsOf lib.types.raw;
          default = { };
        };
        # The system the configuration builds. The store path of the
        # stub names how many system units the configuration has, so
        # a test can tell the system of an evaluation that activates
        # homes from the system of an evaluation that does not.
        system.build.toplevel = lib.mkOption {
          type = lib.types.raw;
          default = {
            outPath = "/nix/store/stub-system-with-${toString (builtins.length (builtins.attrNames config.systemd.services))}-units";
          };
        };
        stub.fromBaseModules = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
      };
      config.stub.fromBaseModules = true;
      # NixOS hands its modules a set of helpers as the argument
      # `utils`. The module that activates homes uses the function
      # that makes a string safe as part of a unit name.
      config._module.args.utils.escapeSystemdPath = name: name;
    }
  )
]
