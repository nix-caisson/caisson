# SPDX-License-Identifier: MIT
#
# A home-manager module for a home that is declared inside a NixOS
# configuration. It sets the options of the home that come from the
# machine.
#
# home-manager has a NixOS module that embeds homes in a machine. For
# each home, that module sets a few options of the home from the
# machine: the home directory and the user ID from the account the
# machine declares, and the Nix package the machine runs. caisson does
# not use that NixOS module. A home declared inside a NixOS
# configuration is a caisson configuration, and this module gives it
# the same settings.
#
# caisson's `default` home-manager module imports this module in a
# home that is declared inside a NixOS configuration. A home that
# passes `moduleImports` selects its modules itself, and gets this
# module only if it lists it.
#
# The module reads the machine through the manifest of the home, so it
# can only be imported by a home that has a NixOS configuration above
# it.
{ ... }:
# `lib` is the library of the home, and `config` is the configuration
# of the home.
{ lib, config, ... }:
let
  # The configuration of the NixOS configuration the home is declared
  # inside. The home reads the childless evaluation of the NixOS
  # configuration, which is the evaluation that leaves out the
  # configurations declared inside it. The home is one of those
  # configurations, so it cannot read an evaluation that includes it.
  machine = lib.caisson.evalManifest.nearest.nixos.value.config;

  # The account of the user of the home, when the NixOS configuration
  # declares one in `users.users`. It is null when the NixOS
  # configuration declares no such account. That is the case for an
  # account that systemd-homed manages. It is also null in a NixOS
  # configuration that has no `users` options, which the nixos-minimal
  # integration can produce.
  account = (machine.users.users or { }).${config.home.username} or null;
in
{
  config = lib.mkMerge [
    {
      # home-manager reads this option to tell that the home is
      # activated by a machine. `externalPackageInstall` stays false,
      # so the activation of the home installs the packages of the
      # home. The NixOS configuration installs none of them.
      submoduleSupport.enable = true;
    }

    # The home is activated with the Nix that the machine runs. A
    # NixOS configuration from the nixos-minimal integration may have
    # no `nix` options, and then the home keeps the settings it has.
    (lib.mkIf (machine ? nix) {
      nix.enable = machine.nix.enable;
      nix.package = lib.mkIf machine.nix.enable machine.nix.package;
    })

    # The home directory and the user ID come from the account, when
    # the NixOS configuration declares the account. A home whose
    # account the NixOS configuration does not declare sets its home
    # directory itself.
    (lib.mkIf (account != null) {
      home.homeDirectory = account.home;
      home.uid = lib.mkIf (account.uid != null) account.uid;
    })

    # home-manager leaves its command-line program out of a home that
    # has `submoduleSupport.enable` set. The program is how the user
    # activates the home by hand, with `home-manager switch`, so it is
    # put back.
    (lib.mkIf config.programs.home-manager.enable {
      home.packages = [ config.programs.home-manager.package ];
    })
  ];
}
