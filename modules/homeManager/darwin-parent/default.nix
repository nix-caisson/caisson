# SPDX-License-Identifier: MIT
#
# A home-manager module for a home that is declared inside a darwin
# configuration. It sets the options of the home that come from the
# machine, as home-manager's nix-darwin module does for the homes it
# embeds: the home directory and the user ID from the account the
# machine declares, and the Nix the machine runs. caisson does not use
# that nix-darwin module.
#
# A darwin configuration adds this module to the modules that the
# homes declared inside it import by default. caisson's `default`
# darwin module does that, through `caisson.forChildren`. A home that
# passes `moduleImports` selects its modules itself, and gets this
# module only if it lists it.
#
# The module reads the machine through the manifest of the home, so it
# can only be imported by a home that has a darwin configuration above
# it.
{ ... }:
# `lib` is the library of the home, and `config` is the configuration
# of the home.
{ lib, config, ... }:
let
  # The configuration of the darwin configuration the home is declared
  # inside, in its childless evaluation, which leaves out the
  # configurations declared inside it.
  machine = lib.caisson.evalManifest.nearest.darwin.value.config;

  # The account of the user of the home, when the machine declares one.
  account = machine.users.users.${config.home.username} or null;

  # nix-darwin can declare `uid` without a value, so it is read with
  # `tryEval`, as home-manager's nix-darwin module reads it.
  uid = if account == null then null else builtins.tryEval account.uid;

  # Why the machine gives the home no home directory, or null when it
  # gives one. nix-darwin leaves `home` at `null` until the machine
  # sets it.
  missing =
    if account == null then
      "declares no account for the user `${config.home.username}` in `users.users`"
    else if account.home == null then
      "sets no home directory in `users.users.${config.home.username}.home`, which nix-darwin leaves at `null`"
    else
      null;
in
{
  config = lib.mkMerge [
    {
      # home-manager reads this option to tell that the home is
      # activated by a machine. `externalPackageInstall` stays false,
      # so the activation of the home installs the packages of the home.
      submoduleSupport.enable = true;

      nix.enable = machine.nix.enable;
      nix.package = lib.mkIf machine.nix.enable machine.nix.package;
    }

    (lib.mkIf (missing == null) {
      home.homeDirectory = account.home;
    })
    (lib.mkIf (account != null) {
      home.uid = lib.mkIf (uid.success && uid.value != null) uid.value;
    })

    # When the machine gives no home directory, reading the home
    # directory fails with a message that says why. home-manager reads
    # it while it checks the assertions of the home, before the
    # machine's activation module can refuse the home. A home that sets
    # its home directory itself replaces this default, and the
    # activation module refuses that home.
    (lib.mkIf (missing != null) {
      home.homeDirectory = lib.mkDefault (
        throw "caisson: the home of `${config.home.username}` is declared inside a darwin configuration that ${missing}."
      );
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
