# SPDX-License-Identifier: MIT
#
# A NixOS test, run in a VM, of home-manager configurations that set
# `caisson.useUserPackages`: the machine installs their packages in
# `/etc/profiles/per-user/<user>`, a switch of the machine changes them
# whether the user is logged in or not, and the activation of each
# home-manager configuration links its files and records its
# generation. `inputs` is the dependency pool of the checks partition
# with `caisson` set to the tree itself.
#
# The home-manager configurations come in the versions v1 and v2. Each
# version installs `hello`, v2 also installs `tree`, and a file and a
# session variable of each home-manager configuration name the version.
#
# The machine declares the account of `carol`, whose home-manager
# configuration sets the option, and the account of `plain`, whose
# home-manager configuration leaves it unset. The account of `dave` is
# declared elsewhere, as systemd-homed declares it, and his home-manager
# configuration sets the option. The specialisation `v2` declares v2.
#
# The test boots the machine in v1 before `dave` has an account. It
# checks that the machine has built the packages of `dave` without any
# activation for him, and that the packages, the files, the session
# variable and the generations of `carol` are those of v1, and that
# `plain` installs his packages into `~/.nix-profile`. It switches to
# v2, which changes the packages of `dave` while he has no home
# directory, then creates his account, which activates his home-manager
# configuration at the start of his service manager. It switches back
# to v1 and to v2 again, checking each step, and boots the machine
# again in v1.
#
# The node is evaluated as in tests/activation-vm: on the library of a
# caisson evaluation of the same machine, with the framework modules of
# the class and caisson's `default` module.
{ inputs }:
let
  core = inputs.caisson.lib.caisson-core;

  system = "x86_64-linux";

  pkgs = import inputs.nixpkgs { inherit system; };

  lib = core.mkLib {
    dependencies = {
      inherit (inputs)
        nixpkgs
        home-manager
        ;
    };
    systems = [ system ];
    projects.caisson = inputs.caisson;
    defaultEcosystemSrc = dependencies: {
      nixpkgs-lib = dependencies.nixpkgs;
      nixos = dependencies.nixpkgs;
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

  # A home-manager configuration in a version, with `extra` merged in.
  # bash is managed by the home-manager configuration, so a login shell
  # reads the session variables of the home-manager configuration from
  # `home.profileDirectory`.
  homeOf =
    version: lib: extra:
    lib.caisson.home-manager.mkConfiguration {
      configModule =
        { pkgs, ... }:
        {
          imports = [ extra ];
          home.stateVersion = "25.05";
          home.packages = [ pkgs.hello ] ++ pkgs.lib.optional (version == "v2") pkgs.tree;
          home.file.".config/probe/version".text = version;
          home.sessionVariables.PROBE_VERSION = version;
          programs.bash.enable = true;
          programs.home-manager.enable = true;
        };
    };

  # What the machine declares in a version. The specialisation `v2`
  # replaces the set of home-manager configurations whole.
  declarationsOf =
    version: lib:
    let
      force = if version == "v1" then (value: value) else lib.mkForce;
    in
    {
      caisson.home-manager.configurations = force {
        carol = homeOf version lib { caisson.useUserPackages = true; };
        dave = homeOf version lib {
          home.homeDirectory = "/home/dave";
          caisson.useUserPackages = true;
        };
        plain = homeOf version lib { };
      };
    };

  machine =
    { lib, ... }:
    {
      config = lib.mkMerge [
        (declarationsOf "v1" lib)
        {
          users.users.carol = {
            isNormalUser = true;
            uid = 1002;
          };
          users.users.plain = {
            isNormalUser = true;
            uid = 1006;
          };
          caisson.home-manager.activation.usersDeclaredElsewhere = [ "dave" ];
        }
      ];
    };

  # The library of the caisson evaluation of the machine, which carries
  # the manifest of that evaluation. A module of the evaluation hands
  # the library out through an option.
  machineLib =
    (lib.caisson.nixos.mkTopConfiguration {
      configModule =
        { lib, ... }:
        {
          imports = [ machine ];
          options.userPackagesVmLib = lib.mkOption { type = lib.types.raw; };
          config = {
            userPackagesVmLib = lib;
            boot.loader.grub.enable = false;
            fileSystems."/" = {
              device = "none";
              fsType = "tmpfs";
            };
            system.stateVersion = "25.05";
          };
        };
    }).config.userPackagesVmLib;

  registry = machineLib.caisson.modules.nixos;
in
pkgs.testers.runNixOSTest {
  name = "caisson-user-packages-vm";

  node.specialArgs.lib = machineLib;

  nodes.machine = {
    imports = machineLib.caisson.integrations.frameworkModules "nixos" registry ++ [
      registry."caisson/default"
      machine
    ];
    system.stateVersion = "25.05";
    # The test switches the machine, which the test framework leaves
    # out of a node by default.
    system.switch.enable = true;
    # The test boots the machine again, and the generations the first
    # boot recorded must still be in the store.
    virtualisation.writableStoreUseTmpfs = false;
    specialisation.v2.configuration = { lib, ... }: declarationsOf "v2" lib;
  };

  testScript =
    { nodes, ... }:
    let
      v1 = nodes.machine.system.build.toplevel;
    in
    ''
      def login(user, command):
          return machine.succeed(f"su -l {user} -c '{command}'").strip()

      def switch_to(toplevel):
          machine.succeed(f"{toplevel}/bin/switch-to-configuration test")

      # The packages the machine installs for `user` are those of
      # `version`: `hello` in both, `tree` in v2 alone. The profile also
      # holds the file with the session variables, which home-manager's
      # `xsession` module reads from there.
      def packages_are(user, version):
          machine.succeed(f"test -x /etc/profiles/per-user/{user}/bin/hello")
          machine.succeed(
              f"grep -q 'PROBE_VERSION=.*{version}' /etc/profiles/per-user/{user}/etc/profile.d/hm-session-vars.sh"
          )
          if version == "v2":
              machine.succeed(f"test -x /etc/profiles/per-user/{user}/bin/tree")
          else:
              machine.fail(f"test -e /etc/profiles/per-user/{user}/bin/tree")

      # The activation of the home-manager configuration of `user` has
      # linked the files of `version`.
      def files_are(user, version):
          machine.wait_until_succeeds(
              f"grep -qx {version} /home/{user}/.config/probe/version", timeout=60
          )

      # A login shell of `user` runs the packages the machine installs,
      # and has the session variable of `version`. The activation
      # installed nothing into `~/.nix-profile`.
      def shell_is(user, version):
          found = login(user, "command -v hello")
          assert found == f"/etc/profiles/per-user/{user}/bin/hello", f"{user} runs {found}"
          variable = login(user, "echo $PROBE_VERSION")
          assert variable == version, f"PROBE_VERSION of {user} is {variable}, not {version}"
          machine.fail(f"test -e /home/{user}/.nix-profile/bin/hello")

      # The generations `home-manager generations` lists for `user`: the
      # last line is the first generation, and the current one is marked.
      def generations_of(user):
          return login(user, "home-manager generations").splitlines()

      # The home-manager configuration of `plain` installs its packages
      # into the profile in its home directory, and the machine builds
      # no `/etc/profiles/per-user/plain`.
      def plain_is(version):
          files_are("plain", version)
          machine.wait_until_succeeds("test -x /home/plain/.nix-profile/bin/hello", timeout=60)
          if version == "v2":
              machine.wait_until_succeeds("test -x /home/plain/.nix-profile/bin/tree", timeout=60)
          else:
              machine.wait_until_fails("test -e /home/plain/.nix-profile/bin/tree", timeout=60)
          machine.fail("test -e /etc/profiles/per-user/plain")
          found = login("plain", "command -v hello")
          assert found == "/home/plain/.nix-profile/bin/hello", f"plain runs {found}"

      def carol_is(version, generations):
          machine.wait_for_unit("home-manager-carol.service")
          packages_are("carol", version)
          files_are("carol", version)
          shell_is("carol", version)
          listed = generations_of("carol")
          assert len(listed) == generations, f"carol has the generations {listed}"
          assert listed[0].endswith("(current)"), f"the generations of carol are {listed}"
          machine.succeed(
              "test $(readlink -f /home/carol/.local/state/nix/profiles/home-manager/home-files/.config/probe/version)"
              " = $(readlink -f /home/carol/.config/probe/version)"
          )

      # The machine boots in v1. The account of `dave` does not exist,
      # so nothing has activated his home-manager configuration, and the
      # machine has built his packages.
      machine.wait_for_unit("multi-user.target")
      carol_is("v1", 1)
      plain_is("v1")
      packages_are("dave", "v1")
      machine.fail("test -e /home/dave")
      # `home-manager packages` reads the profile in the home directory,
      # which holds none of the packages of `carol`.
      status, listed = machine.execute("su -l carol -c 'home-manager packages' 2>&1")
      print(f"home-manager packages of carol: exit {status}: {listed!r}")
      assert "hello" not in listed, f"home-manager packages of carol lists {listed}"

      # A switch to v2 changes the packages of `dave`, who has no home
      # directory yet.
      switch_to("${v1}/specialisation/v2")
      carol_is("v2", 2)
      plain_is("v2")
      packages_are("dave", "v2")
      machine.fail("test -e /home/dave")

      # The account of `dave` is created and lingers, so his service
      # manager starts, and the user unit activates his home-manager
      # configuration: the files of v2, and no package in his home
      # directory.
      machine.succeed("useradd --create-home --uid 1003 --shell /run/current-system/sw/bin/bash dave")
      machine.succeed("loginctl enable-linger dave")
      machine.wait_for_unit("user@1003.service")
      machine.wait_until_succeeds(
          "systemctl --user -M dave@ is-active home-manager-dave.service", timeout=60
      )
      files_are("dave", "v2")
      shell_is("dave", "v2")

      # Back to v1, and to v2 again.
      switch_to("${v1}")
      carol_is("v1", 3)
      plain_is("v1")
      packages_are("dave", "v1")
      switch_to("${v1}/specialisation/v2")
      carol_is("v2", 4)
      packages_are("dave", "v2")

      # The machine boots again in v1: the packages are those of v1, and
      # the activation of `carol` at boot records a new generation.
      machine.shutdown()
      machine.start()
      machine.wait_for_unit("multi-user.target")
      carol_is("v1", 5)
      plain_is("v1")
      packages_are("dave", "v1")
    '';
}
