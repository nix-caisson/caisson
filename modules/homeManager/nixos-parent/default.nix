# SPDX-License-Identifier: MIT
#
# A home-manager module for a home-manager configuration that is
# declared inside a NixOS configuration. It sets the options of the
# home-manager configuration that come from the machine.
#
# home-manager has a NixOS module that embeds home-manager
# configurations in a machine. For each home-manager configuration,
# that module sets a few options of the home-manager configuration from
# the machine: the home directory and the user ID from the account the
# machine declares, and the Nix package the machine runs. caisson does
# not use that NixOS module. A home-manager configuration declared
# inside a NixOS configuration is a caisson configuration, and this
# module gives it the same settings.
#
# A NixOS configuration adds this module to the modules that the
# home-manager configurations declared inside it import by default.
# caisson's `default` NixOS module does that, through
# `caisson.forChildren`. A home-manager configuration that passes
# `moduleImports` selects its modules itself, and gets this module only
# if it lists it. A system-manager configuration does the same with
# this file, registered also as `system-manager-parent`.
#
# The module reads the machine through the manifest of the
# home-manager configuration, so it can only be imported by a
# home-manager configuration that has a NixOS or system-manager
# configuration above it.
{ ... }:
# `lib` is the library of the home-manager configuration, and `config`
# is the configuration of the home-manager configuration.
{ lib, config, ... }:
let
  # The configuration of the machine the home-manager configuration is
  # declared inside, the nearest NixOS or system-manager configuration
  # above it. The home-manager configuration reads the childless
  # evaluation of the machine, which is the evaluation that leaves out
  # the configurations declared inside it. The home-manager
  # configuration is one of those configurations, so it cannot read an
  # evaluation that includes it.
  machine =
    (lib.caisson.integrations.nearestOf [
      "nixos"
      "system-manager"
    ] lib.caisson.evalManifest).value.config;

  # The account of the user of the home-manager configuration, when the
  # NixOS configuration declares one in `users.users`. It is null when
  # the NixOS configuration declares no such account. That is the case
  # for an
  # account that systemd-homed manages. It is also null in a NixOS
  # configuration that has no `users` options, which the nixos-minimal
  # integration can produce.
  account = (machine.users.users or { }).${config.home.username} or null;
in
{
  config = lib.mkMerge [
    {
      # home-manager reads this option to tell that the home-manager
      # configuration is activated by a machine.
      # `externalPackageInstall` stays false, so the activation of the
      # home-manager configuration installs the packages of the
      # home-manager configuration. The NixOS configuration installs
      # none of them.
      submoduleSupport.enable = true;
    }

    # The home-manager configuration is activated with the Nix that the
    # machine runs. A NixOS configuration from the nixos-minimal
    # integration may have no `nix` options, and then the home-manager
    # configuration keeps the settings it has.
    (lib.mkIf (machine ? nix) {
      nix.enable = machine.nix.enable;
      nix.package = lib.mkIf machine.nix.enable machine.nix.package;
    })

    # The home directory and the user ID come from the account, when
    # the NixOS configuration declares the account. A home-manager
    # configuration whose account the NixOS configuration does not
    # declare sets its home directory itself.
    (lib.mkIf (account != null) {
      home.homeDirectory = account.home;
      home.uid = lib.mkIf (account.uid != null) account.uid;
    })

    # home-manager leaves its command-line program out of a
    # home-manager configuration that has `submoduleSupport.enable` set.
    # The program is how the user activates the home-manager
    # configuration by hand, with `home-manager switch`, so it is put
    # back.
    (lib.mkIf config.programs.home-manager.enable {
      home.packages = [ config.programs.home-manager.package ];
    })
  ];
}
