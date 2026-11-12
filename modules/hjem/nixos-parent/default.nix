# SPDX-License-Identifier: MIT
#
# A hjem module for a hjem configuration declared inside a NixOS or
# system-manager configuration. It sets the home directory of the user
# from the account the NixOS or system-manager configuration declares,
# as hjem's NixOS module does for the users it embeds, and refuses a
# user that configuration has no account for.
#
# caisson does not use hjem's NixOS module. A NixOS or system-manager
# configuration adds this module to the modules that the hjem
# configurations declared inside it import by default; caisson's
# `default` module of either class does that, through
# `caisson.forChildren`. The module is registered as `nixos-parent`. A
# hjem configuration that passes `moduleImports` selects its modules
# itself, and gets this module only if it lists it.
#
# The module reads the NixOS or system-manager configuration through
# the manifest of the hjem configuration, so it can only be imported by
# a hjem configuration that has a NixOS or system-manager configuration
# above it.
{ ... }:
# `lib` is the library of the hjem configuration, and `config` holds its
# evaluated options.
{ lib, config, ... }:
let
  # The evaluated options of the NixOS or system-manager configuration
  # the hjem configuration is declared inside, from the result of its
  # childless evaluation, which leaves out the configurations declared
  # inside it.
  parent = lib.caisson.integrations.nearestOf [
    "nixos"
    "system-manager"
  ] lib.caisson.evalManifest;
  parentConfig = parent.value.config;

  # The account of the user, when that configuration declares one.
  account = (parentConfig.users.users or { }).${config.user} or null;
in
{
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = config.enable -> account != null && (account.enable or true);
          message = "The hjem user `${config.user}` has no enabled account in `users.users` of the ${
            { nixos = "NixOS"; }.${parent.type} or parent.type
          } configuration it is declared inside.";
        }
      ];
    }
    (lib.mkIf (account != null) {
      directory = lib.mkDefault account.home;
    })
  ];
}
