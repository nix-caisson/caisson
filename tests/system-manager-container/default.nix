# SPDX-License-Identifier: MIT
#
# A test of what a system-manager machine activates, run with
# system-manager's container test driver
# (`system-manager.lib.containerTest.makeContainerTest`) in a container
# of a distribution, through sequences of changes. `inputs` is the
# dependency pool of the checks partition with `caisson` set to the tree
# itself; `distro` names a distribution of `distros.nix` beside this
# file, whose root filesystem the container runs.
#
# The driver runs the container with systemd-nspawn in the build
# sandbox, which needs the `uid-range` system feature, so Nix must run
# with `auto-allocate-uids = true`. The test is therefore not among the
# checks `nix flake check` builds: it is the output
# `containerTests.x86_64-linux.system-manager-<distro>`, which CI builds
# with that setting, for each distribution.
#
# The machine comes in the versions v1 and v2, which caisson evaluates
# separately (`topOf` below). It declares the profiles of
# the system `editor` and, in v1 alone, `retired`, a hjem configuration
# for `alice` with a profile inside it, a home for `carol` with a
# profile inside it, and in v2 alone a home for `erin`. A file of the
# machine, of each home and of the hjem configuration names the version,
# and the Neovims of v2 have `vim`. The test activates v1, v2 and v1
# again and checks after each step the files, the profiles and the
# units. It checks that activating v2 and v1 puts the profiles of
# `alice` and of the system back after they are changed by hand, and
# that the activation of the home of `carol` in v2, run by hand while
# the machine runs v1, warns of the drift.
{ inputs, distro }:
let
  core = inputs.caisson.lib.caisson-core;

  system = "x86_64-linux";

  pkgs = import inputs.nixpkgs { inherit system; };

  lib = core.mkLib {
    sources = { };
    systems = [ system ];
    projects.caisson = inputs.caisson;
    defaultEcosystemSrc = {
      inherit (inputs)
        nixpkgs
        system-manager
        home-manager
        hjem
        nvf
        ;
    };
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

  editorOf = version: {
    vim.viAlias = true;
    vim.vimAlias = version == "v2";
  };

  # The accounts the machine declares, each with a group of its name,
  # which system-manager creates with userborn.
  accounts = {
    alice = 5000;
    carol = 5002;
    erin = 5004;
  };

  homeOf =
    version: lib:
    lib.caisson.home-manager.mkConfiguration {
      configModule =
        { lib, ... }:
        {
          home.stateVersion = "25.05";
          home.file.".config/probe/version".text = version;
          caisson.nvf.configurations.home-editor = lib.caisson.nvf.mkConfiguration {
            configModule = editorOf version;
          };
        };
    };

  # The top holding the machine `box` in a version.
  topOf =
    version:
    lib.caisson.structural.mkTopConfiguration {
      moduleImports = _modules: [ ];
      configModule =
        { lib, ... }:
        {
          caisson.system-manager.configurations.box = lib.caisson.system-manager.mkConfiguration {
            configModule =
              { lib, ... }:
              {
                system-manager.allowAnyDistro = true;
                nix.enable = true;
                services.userborn.enable = true;
                users.groups = builtins.mapAttrs (_name: uid: { gid = uid; }) accounts;
                users.users = builtins.mapAttrs (name: uid: {
                  isNormalUser = true;
                  inherit uid;
                  group = name;
                  home = "/home/${name}";
                  createHome = true;
                }) accounts;
                environment.etc."probe/version".text = version;
                caisson.profiles.selected.CAISSON_NVIM_PROFILE = "nvf/editor";
                caisson.nvf.configurations = {
                  editor = lib.caisson.nvf.mkConfiguration { configModule = editorOf version; };
                }
                // lib.optionalAttrs (version == "v1") {
                  retired = lib.caisson.nvf.mkConfiguration { configModule = editorOf version; };
                };
                caisson.hjem.configurations.alice = lib.caisson.hjem.mkConfiguration {
                  configModule =
                    { lib, ... }:
                    {
                      files.".config/probe/version".text = version;
                      caisson.nvf.configurations.hjem-editor = lib.caisson.nvf.mkConfiguration {
                        configModule = editorOf version;
                      };
                    };
                };
                caisson.home-manager.configurations = {
                  carol = homeOf version lib;
                }
                // lib.optionalAttrs (version == "v2") {
                  erin = homeOf version lib;
                };
              };
          };
        };
    };

  v1 = (topOf "v1").systemConfigs.box;
  v2 = (topOf "v2").systemConfigs.box;
  carolV1 = (topOf "v1").homeConfigurations."carol@box".activationPackage;
  carolV2 = (topOf "v2").homeConfigurations."carol@box".activationPackage;

  profile = "/nix/var/nix/profiles/caisson/nvf/editor";
in
inputs.system-manager.lib.containerTest.makeContainerTest {
  hostPkgs = pkgs;
  # The name of the container, which systemd-nspawn takes as a host
  # name, where `_` is not allowed.
  name = builtins.replaceStrings [ "_" ] [ "-" ] "caisson-system-manager-${distro}";
  rootfs = (import ./distros.nix { inherit inputs pkgs; }).${distro};
  toplevel = v1;
  extraPathsToRegister = [
    v2
    carolV1
    carolV2
  ];
  testScript = ''
    import time

    # The driver's `execute` returns a `subprocess.CompletedProcess`.
    def wait_until_fails(command, timeout=60):
        for _ in range(timeout):
            if machine.execute(command).returncode != 0:
                return
            time.sleep(1)
        raise Exception(f"`{command}` still succeeds")

    def profile_of(user, name):
        return f"/home/{user}/.local/state/caisson/profiles/nvf/{name}"

    def target_of(path):
        return machine.succeed(f"readlink -f {path}").strip()

    def change_by_hand(path, user):
        machine.succeed(
            f"runuser -u {user} -- nix-env --profile {path} --set ${v1}"
        )
        machine.fail(f"test -e {path}/bin/nvim")

    # The profile at `path` holds the Neovim of `version`: v2 has `vim`.
    def holds(path, version):
        machine.wait_until_succeeds(f"test -x {path}/bin/nvim", timeout=60)
        if version == "v2":
            machine.wait_until_succeeds(f"test -x {path}/bin/vim", timeout=60)
        else:
            wait_until_fails(f"test -e {path}/bin/vim")

    def names(path, version):
        machine.wait_until_succeeds(f"grep -qx {version} {path}", timeout=60)

    def is_at(version):
        names("/etc/probe/version", version)
        holds("${profile}", version)
        for user, name in [("alice", "hjem-editor"), ("carol", "home-editor")]:
            holds(profile_of(user, name), version)
            names(f"/home/{user}/.config/probe/version", version)

    def activate(toplevel):
        logs = machine.activate(profile=toplevel)
        for line in logs.split("\n"):
            assert "ERROR" not in line, line
        machine.wait_for_unit("system-manager.target")

    start_all()
    machine.wait_for_unit("multi-user.target")

    # v1: everything is v1, and the profile `retired` is activated.
    activate("${v1}")
    is_at("v1")
    holds("/nix/var/nix/profiles/caisson/nvf/retired", "v1")
    machine.fail("systemctl cat home-manager-erin.service")
    declared = target_of("${profile}")
    alice_declared = target_of(profile_of("alice", "hjem-editor"))

    # v2: everything follows, `retired` is gone, and the home of `erin`
    # is activated.
    activate("${v2}")
    is_at("v2")
    machine.fail("systemctl cat caisson-profile-nvf-retired.service")
    machine.wait_for_unit("home-manager-erin.service")
    holds(profile_of("erin", "home-editor"), "v2")
    names("/home/erin/.config/probe/version", "v2")

    # v1 again: everything follows, and the home of `erin` is gone.
    activate("${v1}")
    is_at("v1")
    machine.fail("systemctl cat home-manager-erin.service")

    # system-manager restarts a unit when it changes, so the profiles
    # are activated again when the version changes. After they are
    # changed by hand, activating v2 and then v1 puts the declared
    # Neovims back.
    change_by_hand("${profile}", "root")
    change_by_hand(profile_of("alice", "hjem-editor"), "alice")
    activate("${v2}")
    is_at("v2")
    activate("${v1}")
    is_at("v1")
    restored = target_of("${profile}")
    assert restored == declared, f"the profile is {restored}, not {declared}"
    restored = target_of(profile_of("alice", "hjem-editor"))
    assert restored == alice_declared, f"the profile of alice is {restored}, not {alice_declared}"

    # The activation of the home of `carol` in v2, run by hand while the
    # machine runs v1, warns of the drift and applies the home; the
    # activation in v1 is quiet.
    out = machine.succeed("runuser -u carol -- ${carolV2}/activate 2>&1")
    assert "was built for a version of the system-manager configuration" in out, out
    names("/home/carol/.config/probe/version", "v2")
    out = machine.succeed("runuser -u carol -- ${carolV1}/activate 2>&1")
    assert "WARNING" not in out, out
    names("/home/carol/.config/probe/version", "v1")
  '';
}
