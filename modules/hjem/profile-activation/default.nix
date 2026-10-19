# SPDX-License-Identifier: MIT
#
# A hjem module for the profiles declared inside a hjem configuration:
# the configurations that are programs a person runs, such as an nvf or
# nixvim Neovim, each kept in a profile of the user,
# `$HOME/.local/state/caisson/profiles/<kind>/<name>`
# (`lib.caisson.integrations.profileOf`).
#
# hjem's activation has no step a configuration can add, so the machine
# the hjem configuration is declared inside activates the profiles, as
# the user, after the hjem configuration is applied (the module
# `profile-activation` of the class of the machine). This module adds
# to the packages of the user the programs with which a shell chooses
# among profiles (`lib.caisson.integrations.profileShimsOf`), and sets
# the variable that chooses, `CAISSON_NVIM_PROFILE` for a Neovim, to the
# profile of the user, so that the programs the machine installs choose
# the same.
#
# A hjem configuration with no machine above it is applied with
# `hjem standalone switch`, and no machine activates its profiles. On
# Linux, this module adds to its files the systemd user units that do.
# The service `caisson-profiles` runs the `activate` of each profile,
# and is wanted by `default.target`, so it runs when the user's systemd
# starts. The path unit `caisson-profiles` starts the service when the
# manifest hjem keeps for the current generation changes,
# `$XDG_STATE_HOME/hjem/standalone/current/manifest.json` (`%S` in a
# unit of the user), which `hjem standalone switch` writes at every
# switch. The units are read by the user's systemd once it reloads, so
# the switch that first adds them activates the profiles at the next
# login, or after `systemctl --user daemon-reload` and
# `systemctl --user start caisson-profiles.path caisson-profiles.service`.
#
# On macOS, the module adds the launchd agent `org.caisson.profiles` to
# the files, as `~/Library/LaunchAgents/org.caisson.profiles.plist`. The
# agent runs the `activate` of each profile when launchd loads it, which
# it does at login, and when the manifest of the current generation
# changes. launchd expands no variables in the paths an agent watches,
# so the agent watches the manifest where hjem keeps it when
# `XDG_STATE_HOME` is unset,
# `~/.local/state/hjem/standalone/current/manifest.json`. The switch that
# first adds the agent activates the profiles at the next login, or
# after `launchctl bootstrap gui/$(id -u)
# ~/Library/LaunchAgents/org.caisson.profiles.plist`.
#
# caisson's `default` hjem module imports this module. It defines
# nothing in the childless evaluation.
{ ... }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.caisson) evalManifest;
  selection = lib.caisson.integrations;

  profiles = selection.profilesActivatedBy evalManifest config.caisson.exports.configurations;

  choices = selection.profileChoicesOf {
    selected = config.caisson.profiles.selected;
    what = "this hjem configuration";
  } profiles;

  # The path of a profile, with `$HOME` written out as the directory of
  # the user, for a variable hjem writes as given.
  pathOf =
    choice:
    builtins.replaceStrings [ "$HOME" ] [ config.directory ]
      choice.chosen.manifest.outputs.profile.path;

  # True when no machine applies this hjem configuration: there is no
  # configuration above it with an activation.
  standalone = selection.activatingAncestorOf evalManifest == null;

  onLinux = lib.hasSuffix "-linux" (evalManifest.system or "");
  onDarwin = lib.hasSuffix "-darwin" (evalManifest.system or "");

  activateProfiles = pkgs.writeShellScript "caisson-profiles" (
    lib.concatMapStrings (entry: ''
      ${entry.manifest.outputs.activationPackage}/activate
    '') profiles
  );

  # Each unit is a file named as the unit, so that the links to it in
  # `default.target.wants` and `paths.target.wants` point at a file of
  # the same name, which systemd requires of such a link.
  unitFile = name: text: "${pkgs.writeTextDir name text}/${name}";

  serviceUnit = unitFile "caisson-profiles.service" ''
    [Unit]
    Description=Activate the profiles of the hjem configuration

    [Service]
    Type=oneshot
    ExecStart=${activateProfiles}
  '';

  pathUnit = unitFile "caisson-profiles.path" ''
    [Unit]
    Description=Activate the profiles of the hjem configuration when hjem switches

    [Path]
    PathChanged=%S/hjem/standalone/current/manifest.json
    Unit=caisson-profiles.service
  '';

  # The directory of the user's systemd units, relative to the home
  # directory, as hjem's `files` names a file.
  units = ".config/systemd/user";

  agent = pkgs.writeText "org.caisson.profiles.plist" (
    lib.generators.toPlist { escape = true; } {
      Label = "org.caisson.profiles";
      ProgramArguments = [ "${activateProfiles}" ];
      RunAtLoad = true;
      WatchPaths = [ "${config.directory}/.local/state/hjem/standalone/current/manifest.json" ];
    }
  );
in
{
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
      profiles declared inside this hjem configuration share a variable.
    '';
  };

  config = lib.mkIf (!evalManifest.childless && profiles != [ ]) {
    files = lib.mkMerge [
      (lib.mkIf (standalone && onLinux) {
        "${units}/caisson-profiles.service".source = serviceUnit;
        "${units}/default.target.wants/caisson-profiles.service".source = serviceUnit;
        "${units}/caisson-profiles.path".source = pathUnit;
        "${units}/paths.target.wants/caisson-profiles.path".source = pathUnit;
      })
      (lib.mkIf (standalone && onDarwin) {
        "Library/LaunchAgents/org.caisson.profiles.plist".source = agent;
      })
    ];

    packages = lib.mapAttrsToList (
      variable: choice:
      selection.profileShimsOf {
        inherit pkgs variable;
        inherit (choice) programs;
        fallback = pathOf choice;
      }
    ) choices;

    environment.sessionVariables = builtins.mapAttrs (_variable: pathOf) choices;
  };
}
