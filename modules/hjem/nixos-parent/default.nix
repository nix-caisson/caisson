# SPDX-License-Identifier: MIT
#
# An hjem module for an hjem configuration declared inside a NixOS or
# system-manager configuration. It sets the home directory of the user
# from the account the machine declares, as hjem's NixOS module does for
# the users it embeds, and refuses a user the machine has no account
# for.
#
# caisson does not use hjem's NixOS module. A NixOS or system-manager
# configuration adds this module to the modules that the hjem
# configurations declared inside it import by default; caisson's
# `default` module of either class does that, through
# `caisson.forChildren`. The module is registered as `nixos-parent` and,
# for the same file, as `system-manager-parent`. An hjem configuration
# that passes `moduleImports` selects its modules itself, and gets this
# module only if it lists it.
#
# The module reads the machine through the manifest of the hjem
# configuration, so it can only be imported by an hjem configuration
# that has a NixOS or system-manager configuration above it.
{ ... }:
# `lib` is the library of the hjem configuration, and `config` is its
# configuration.
{ lib, config, ... }:
let
  # The configuration of the machine the hjem configuration is declared
  # inside, in its childless evaluation, which leaves out the
  # configurations declared inside it.
  machine =
    (lib.caisson.integrations.nearestOf [
      "nixos"
      "system-manager"
    ] lib.caisson.evalManifest).value.config;

  # The account of the user, when the machine declares one.
  account = (machine.users.users or { }).${config.user} or null;
in
{
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = config.enable -> account != null && (account.enable or true);
          message = "The hjem user `${config.user}` has no enabled account in `users.users` of the machine it is declared inside.";
        }
      ];
    }
    (lib.mkIf (account != null) {
      directory = lib.mkDefault account.home;
    })
  ];
}
