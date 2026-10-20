# SPDX-License-Identifier: MIT
#
# A module with which a machine activates the profiles declared inside
# it: the configurations that are programs a person runs, such as an
# nvf or nixvim Neovim, each kept in a Nix profile of its own
# (`lib.caisson.integrations.profileOf`).
#
# A profile declared directly inside the machine is a profile of the
# system, `/nix/var/nix/profiles/caisson/<kind>/<name>`. The module
# writes a system unit for each, `caisson-profile-<kind>-<name>`, which
# runs its `activate` as root. The unit is wanted by
# `multi-user.target`, so it runs at boot and again when a switch
# changes it, and the profile is put back to what the machine declares
# each time.
#
# A profile declared inside a hjem configuration inside the machine is
# a profile of the hjem user. hjem's activation has no step a
# configuration can add, so the machine activates it, with a unit
# `caisson-profile-<user>-<kind>-<name>` that runs as the user after
# `hjem-activate@<user>` has applied the hjem configuration. The unit is
# wanted by `hjem.target` and is part of it. The machine starts
# `hjem.target` at boot, and stops and starts it again at every switch
# (`X-StopOnReconfiguration`, in the module `hjem-activation`), so the
# profile is activated each time the files of the user are applied. A
# profile inside a home-manager configuration is activated by the
# home-manager configuration.
#
# The machine also installs, in `environment.systemPackages`, the
# programs with which a shell chooses among the profiles of the system
# (`lib.caisson.integrations.profileShimsOf`): `nvim` runs the Neovim of
# the profile `$CAISSON_NVIM_PROFILE` names, and of the default profile
# of the machine when it is unset. A home-manager configuration or a
# hjem configuration sets the variable to its own profile.
#
# The module is registered for the `nixos` and `systemManager` classes,
# under the same name, and the `default` module of each imports it.
# system-manager starts the units wanted by `multi-user.target` with
# `system-manager.target`. It defines nothing in the childless
# evaluation, or in an evaluation without systemd options.
{ closure-lib, ... }:
{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  inherit (lib.caisson) evalManifest;
  selection = lib.caisson.integrations;

  hasUnits = options ? systemd && options.systemd ? services;
  hasPackages = options ? environment && options.environment ? systemPackages;

  coreModule =
    if (evalManifest.type or null) == "system-manager" then
      closure-lib.caisson.modules.systemManager.core
    else
      closure-lib.caisson.modules.nixos.core;

  exported = config.caisson.exports.configurations;

  ofSystem = selection.profilesActivatedBy evalManifest exported;

  # The hjem configurations this machine activates, each with the
  # profiles declared inside it, which the machine passes up as well. On
  # system-manager the unit that applies the files of a hjem user also
  # activates these profiles (the module `hjem-activation`), so this
  # module writes no unit for them there.
  hjemUsers =
    if (evalManifest.type or null) == "system-manager" then
      [ ]
    else
      builtins.map
        (entry: {
          inherit (entry.manifest.value.config) user;
          profiles = selection.profilesActivatedBy entry.manifest exported;
        })
        (
          builtins.filter (
            entry: entry.manifest.type == "hjem" && selection.checksMarkerOf evalManifest entry
          ) exported
        );

  # The parts of a unit name: the name of a profile has no `/`
  # (`lib.caisson.integrations.safeName`), and a user name is used as
  # the module `hjem-activation` uses it for `hjem-activate@<user>`.
  escape = part: part;

  unitOf =
    {
      entry,
      user ? null,
    }:
    let
      inherit (entry.manifest.outputs) profile activationPackage;
    in
    {
      name =
        if user == null then
          "caisson-profile-${escape profile.kind}-${escape profile.name}"
        else
          "caisson-profile-${escape user}-${escape profile.kind}-${escape profile.name}";
      value = {
        description = "Activate the ${profile.kind} profile ${profile.name}${
          if user == null then "" else " of ${user}"
        }";
        wantedBy = if user == null then [ "multi-user.target" ] else [ "hjem.target" ];
        partOf = if user == null then [ ] else [ "hjem.target" ];
        wants = [ "nix-daemon.socket" ];
        after = [
          "nix-daemon.socket"
        ]
        ++ (if user == null then [ ] else [ "hjem-activate@${escape user}.service" ]);
        # The unit is not stopped when its definition changes; the new
        # generation starts it again, which activates the new profile.
        stopIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${activationPackage}/activate";
        }
        // (if user == null then { } else { User = user; });
      };
    };

  choices = selection.profileChoicesOf {
    selected = config.caisson.profiles.selected;
    what = "this machine";
  } ofSystem;

  shims = lib.mapAttrsToList (
    variable: choice:
    selection.profileShimsOf {
      inherit pkgs variable;
      inherit (choice) programs;
      fallback = choice.chosen.manifest.outputs.profile.path;
    }
  ) choices;
in
{
  imports = [ coreModule ];

  options.caisson.profiles.selected = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    example = {
      CAISSON_NVIM_PROFILE = "nvf/editor";
    };
    description = ''
      By the variable that chooses among them, the profile a shell runs
      when it sets no other, as `<kind>/<name>`: `nvf/editor` is the nvf
      configuration declared as `editor`. Needed only where several
      profiles declared inside this configuration share a variable.
    '';
  };

  # `optionalAttrs` and not `mkIf` decides whether each option is
  # defined at all: NixOS refuses a definition, even under `mkIf false`,
  # of an option that no module declares, and the nixos-minimal
  # integration can produce an evaluation without these options.
  config = lib.mkIf (!evalManifest.childless) (
    lib.optionalAttrs hasUnits {
      systemd.services = builtins.listToAttrs (
        builtins.map (entry: unitOf { inherit entry; }) ofSystem
        ++ builtins.concatMap (
          hjem:
          builtins.map (
            entry:
            unitOf {
              inherit entry;
              inherit (hjem) user;
            }
          ) hjem.profiles
        ) hjemUsers
      );
    }
    // lib.optionalAttrs hasPackages {
      environment.systemPackages = shims;
    }
  );
}
