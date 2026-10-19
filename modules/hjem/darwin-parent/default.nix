# SPDX-License-Identifier: MIT
#
# A hjem module for a hjem configuration declared inside a darwin
# configuration. It sets the home directory of the user from the
# account the machine declares, as hjem's nix-darwin module does for
# the users it embeds. It refuses a user the machine has no account
# for, and a user whose account sets no home directory, which
# nix-darwin leaves at `null` until the machine sets it.
#
# caisson does not use hjem's nix-darwin module. A darwin configuration
# adds this module to the modules that the hjem configurations declared
# inside it import by default; caisson's `default` darwin module does
# that, through `caisson.forChildren`. A hjem configuration that passes
# `moduleImports` selects its modules itself, and gets this module only
# if it lists it.
#
# The module reads the machine through the manifest of the hjem
# configuration, so it can only be imported by a hjem configuration
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
        {
          assertion = config.enable && account != null -> account.home != null;
          message = "The account of the hjem user `${config.user}` sets no home directory in `users.users.${config.user}.home` of the darwin configuration it is declared inside.";
        }
      ];
    }
    # When the machine gives no home directory, reading `directory`
    # fails with the message of the assertion that refuses the user, in
    # case it is read before the assertions are checked.
    {
      directory = lib.mkDefault (
        if account == null then
          throw "caisson: the hjem user `${config.user}` has no account in `users.users` of the darwin configuration it is declared inside."
        else if account.home == null then
          throw "caisson: the account of the hjem user `${config.user}` sets no home directory in `users.users.${config.user}.home` of the darwin configuration it is declared inside."
        else
          account.home
      );
    }
  ];
}
