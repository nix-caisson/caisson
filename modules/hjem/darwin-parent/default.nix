# SPDX-License-Identifier: MIT
#
# An hjem module for an hjem configuration declared inside a darwin
# configuration. It sets the home directory of the user from the
# account the machine declares, as hjem's nix-darwin module does for
# the users it embeds, and refuses a user the machine has no account
# for.
#
# caisson does not use hjem's nix-darwin module. A darwin configuration
# adds this module to the modules that the hjem configurations declared
# inside it import by default; caisson's `default` darwin module does
# that, through `caisson.forChildren`. An hjem configuration that passes
# `moduleImports` selects its modules itself, and gets this module only
# if it lists it.
#
# The module reads the machine through the manifest of the hjem
# configuration, so it can only be imported by an hjem configuration
# that has a darwin configuration above it.
{ ... }:
# `lib` is the library of the hjem configuration, and `config` is its
# configuration.
{ lib, config, ... }:
let
  machine = lib.caisson.evalManifest.nearest.darwin.value.config;
  account = machine.users.users.${config.user} or null;
in
{
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = config.enable -> account != null;
          message = "The hjem user `${config.user}` has no account in `users.users` of the darwin configuration it is declared inside.";
        }
      ];
    }
    (lib.mkIf (account != null) {
      directory = lib.mkDefault account.home;
    })
  ];
}
