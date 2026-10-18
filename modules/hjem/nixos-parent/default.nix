# SPDX-License-Identifier: MIT
#
# A hjem module for a hjem configuration declared inside a NixOS
# configuration. It sets the home directory of the user from the
# account the machine declares, as hjem's NixOS module does for the
# users it embeds, and refuses a user the machine has no account for.
#
# caisson does not use hjem's NixOS module. A NixOS configuration adds
# this module to the modules that the hjem configurations declared
# inside it import by default; caisson's `default` NixOS module does
# that, through `caisson.forChildren`. A hjem configuration that
# passes `moduleImports` selects its modules itself, and gets this
# module only if it lists it.
#
# The module reads the machine through the manifest of the hjem
# configuration, so it can only be imported by a hjem configuration
# that has a NixOS configuration above it.
{ ... }:
# `lib` is the library of the hjem configuration, and `config` is its
# configuration.
{ lib, config, ... }:
let
  # The configuration of the NixOS configuration the hjem configuration
  # is declared inside, in its childless evaluation, which leaves out
  # the configurations declared inside it.
  machine = lib.caisson.evalManifest.nearest.nixos.value.config;

  # The account of the user, when the machine declares one.
  account = (machine.users.users or { }).${config.user} or null;
in
{
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = config.enable -> account != null && (account.enable or true);
          message = "The hjem user `${config.user}` has no enabled account in `users.users` of the NixOS configuration it is declared inside.";
        }
      ];
    }
    (lib.mkIf (account != null) {
      directory = lib.mkDefault account.home;
    })
  ];
}
