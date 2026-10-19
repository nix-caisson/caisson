# SPDX-License-Identifier: MIT
#
# A NixOS module with which a machine activates the hjem configurations
# declared inside it.
#
# Activating a hjem configuration means applying its manifest with
# hjem's CLI: `hjem internal activate` links the user's files and
# replaces those of the previous generation, whose manifest is kept in
# `/var/lib/hjem/manifest-<user>.json`. hjem has a NixOS module that
# does this for the users it embeds. caisson does not use that NixOS
# module. A hjem configuration declared inside a NixOS configuration
# is a caisson configuration, and this module writes the units hjem's
# NixOS module writes, under the same names. Each template unit has an
# instance for each user:
#
#   - `hjem-activate@<user>` runs as the user and links the files of the
#     new manifest, given the stored manifest of the previous one;
#   - `hjem-reload@<user>` runs as the user after it and reloads the
#     user's systemd units the change touched;
#   - `hjem-update-state@<user>` stores the new manifest as the state;
#
# and `hjem-cleanup` removes the stored manifests of users that are no
# longer activated. The target `hjem` requires them all, and starts at
# boot and when the machine switches to a new generation. The units
# link with hjem's own CLI and the backup prefix of hjem's NixOS
# module; hjem's options for another linker are not offered here.
#
# The module also installs each user's `packages` for that user and
# keeps each user's `extraDependencies` in the closure of the system,
# as hjem's NixOS module does.
#
# Which configurations: the hjem configurations this NixOS
# configuration passes up, leaving out those declared inside a NixOS
# configuration that is itself inside this one, and those evaluated for
# another system. caisson's `default` NixOS module imports this module.
# A NixOS configuration that passes `moduleImports` activates its hjem
# configurations only if it lists it.
#
# The module reads the hjem configurations from the full evaluation of
# the NixOS configuration; in the childless evaluation, and in an
# evaluation without systemd options, it defines nothing.
#
# The same module is registered for the `systemManager` class, under
# the same name, and a system-manager machine activates the hjem
# configurations declared inside it the same way, with the units
# written for each user rather than as templates (`perUser` below). system-manager has no
# `system.extraDependencies`, so there the module keeps no extra
# dependencies in the system. The module reads
# `config.caisson.exports.configurations`, which the core module
# declares; it imports the core module of the class of the evaluation,
# read from its manifest.
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

  # True when this evaluation declares the options the module defines.
  hasUnits =
    options ? systemd && options.systemd ? services && options.systemd ? targets && options ? users;

  # True when the evaluation keeps extra dependencies in the system.
  hasExtraDependencies = options ? system && options.system ? extraDependencies;

  # The core module of the class of this evaluation: of the
  # `systemManager` class in a system-manager evaluation, else of the
  # `nixos` class. The registered core modules of the two classes are
  # one file under two names, so a module imports the one its
  # evaluation already holds.
  coreModule =
    if (lib.caisson-core.evalManifest.type or null) == "system-manager" then
      closure-lib.caisson.modules.systemManager.core
    else
      closure-lib.caisson.modules.nixos.core;

  # The integrations whose configurations are machines.
  machineTypes = [
    "nixos"
    "darwin"
    "system-manager"
  ];

  isActivatedHere =
    entry:
    entry.manifest.type == "hjem"
    && !(builtins.any (segment: builtins.elem segment.type machineTypes) (lib.lists.init entry.path))
    && entry.manifest.system == evalManifest.system;

  # What the units need of each enabled hjem configuration.
  users =
    builtins.map
      (entry: {
        inherit (entry.manifest.value.config)
          user
          directory
          packages
          extraDependencies
          ;
        inherit (entry.manifest.outputs) manifestFile cli;
      })
      (
        builtins.filter (entry: isActivatedHere entry && entry.manifest.value.config.enable) (
          config.caisson.exports.configurations
        )
      );

  # The manifests of the previous generations, which the units read and
  # write, and the manifests of this generation, one file per user.
  oldManifests = "/var/lib/hjem";
  newManifests = pkgs.linkFarm "hjem-manifests" (
    builtins.map (user: {
      name = "manifest-${user.user}.json";
      path = user.manifestFile;
    }) users
  );
  homeDirectories = builtins.map (user: user.directory) users;

  # The prefix hjem's CLI gives the backup of a file it replaces, the
  # default of hjem's NixOS module.
  prefix = ".backup-";

  # The start of each template unit: it stops for a user no hjem
  # configuration here names, and sets `hjem` to the CLI of the
  # configuration of the user. Each hjem configuration builds the CLI
  # from the hjem source it is evaluated with.
  selectUser = ''
    case "$1" in
      ${lib.concatMapStrings (user: ''
        ${lib.escapeShellArg user.user}) hjem=${lib.getExe user.cli} ;;
      '') users}
      *) echo "User '$1' is not configured for hjem" >&2; exit 0 ;;
    esac
  '';

  # The steps of applying the files of a user, each a script that takes
  # the user: linking the files of the new manifest, given the stored
  # manifest of the previous generation, as the user; reloading the
  # systemd units of the user the change touched, as the user; and
  # storing the new manifest as the state, as root.
  activateStep = pkgs.writeShellScript "hjem-activate-step" ''
    set -euo pipefail
    ${selectUser}
    "$hjem" internal activate \
      --manifest "${newManifests}/manifest-$1.json" \
      --state "${oldManifests}/manifest-$1.json" \
      --skip-state-update \
      --prefix "${prefix}" \
      --json
  '';

  reloadStep = pkgs.writeShellScript "hjem-reload-step" ''
    set -euo pipefail
    export PATH=${
      lib.makeBinPath [
        config.systemd.package
        pkgs.coreutils-full
      ]
    }:$PATH
    ${selectUser}
    XDG_RUNTIME_DIR=$(loginctl show-user "$1" --property=RuntimePath --value 2>/dev/null || true)
    if [ -z "$XDG_RUNTIME_DIR" ]; then
      echo "Could not determine XDG runtime directory for $1. Skipping."
      exit 0
    fi
    export XDG_RUNTIME_DIR

    systemd_status=$(systemctl --user is-system-running 2>&1 || true)
    if [ "$systemd_status" != "running" ] && [ "$systemd_status" != "degraded" ]; then
      echo "User systemd for $1 is not running (status: $systemd_status). Skipping."
      exit 0
    fi

    "$hjem" internal reload-actions \
      --old-manifest "${oldManifests}/manifest-$1.json" \
      --new-manifest "${newManifests}/manifest-$1.json" \
      --user "$1" \
      --require-running-systemd
  '';

  updateStateStep = pkgs.writeShellScript "hjem-update-state-step" ''
    set -euo pipefail
    ${selectUser}
    "$hjem" internal update-state \
      --manifest "${newManifests}/manifest-$1.json" \
      --state "${oldManifests}/manifest-$1.json"
  '';

  # On NixOS the steps are the template units of hjem, `hjem-activate@`,
  # `hjem-reload@` and `hjem-update-state@`, with an instance for each
  # user, which `hjem.target` requires and starts in order. A switch
  # stops and starts `hjem.target` (`X-StopOnReconfiguration`), which
  # runs the instances again.
  #
  # system-manager does neither: it reloads a changed unit by its name,
  # which fails for a template, it restarts each changed unit apart, so
  # the order between the instances does not hold, and it does not stop
  # `hjem.target`. So on system-manager the machine writes a single unit
  # for each user, `hjem-activate@<user>`, which runs the steps in order.
  # Its script names the manifests of this generation, so the unit
  # changes when the files of a user change, and system-manager restarts
  # it.
  onSystemManager = (lib.caisson-core.evalManifest.type or null) == "system-manager";

  # The units `hjem.target` requires for a user.
  unitsOf =
    user:
    if onSystemManager then
      [ "hjem-activate@${user.user}.service" ]
    else
      [
        "hjem-activate@${user.user}.service"
        "hjem-reload@${user.user}.service"
        "hjem-update-state@${user.user}.service"
      ];

  # The users that more than one hjem configuration names, which would
  # both write the files of that user.
  names = builtins.map (user: user.user) users;
  repeated = lib.lists.unique (
    builtins.filter (name: lib.lists.count (other: other == name) names > 1) names
  );
in
{
  # The core module of the class of this evaluation, which declares
  # `config.caisson.exports.configurations`.
  imports = [ coreModule ];

  # `optionalAttrs` and not `mkIf` decides whether the options are
  # defined at all: NixOS refuses a definition, even under `mkIf false`,
  # of an option that no module declares.
  config = lib.optionalAttrs hasUnits (
    lib.mkIf (!evalManifest.childless && users != [ ]) {
      assertions = [
        {
          assertion = repeated == [ ];
          message = "caisson: this machine activates more than one hjem configuration for ${lib.concatStringsSep ", " repeated}.";
        }
      ];

      users.users = builtins.listToAttrs (
        builtins.map (user: {
          name = user.user;
          value.packages = user.packages;
        }) users
      );

      system = lib.optionalAttrs hasExtraDependencies {
        extraDependencies = builtins.concatMap (user: user.extraDependencies) users;
      };

      systemd.targets.hjem = {
        description = "hjem file management";
        unitConfig.X-StopOnReconfiguration = true;
        after = [ "local-fs.target" ];
        wantedBy = [
          "sysinit-reactivation.target"
          "multi-user.target"
        ];
        before = [ "sysinit-reactivation.target" ];
        requires = builtins.concatMap unitsOf users ++ [ "hjem-cleanup.service" ];
      };

      systemd.services = {
        hjem-prepare = {
          description = "Prepare Hjem manifests directory";
          enableStrictShellChecks = true;
          script = "mkdir -p ${oldManifests}";
          serviceConfig.Type = "oneshot";
          unitConfig.RefuseManualStart = true;
        };

      }
      // (
        if onSystemManager then
          builtins.listToAttrs (
            builtins.map (user: {
              name = "hjem-activate@${user.user}";
              value = {
                description = "Apply the files of %i from their manifest";
                enableStrictShellChecks = true;
                unitConfig.RequiresMountsFor = homeDirectories;
                serviceConfig.Type = "oneshot";
                requires = [ "hjem-prepare.service" ];
                after = [ "hjem-prepare.service" ];
                scriptArgs = "%i";
                script = ''
                  ${pkgs.util-linux}/bin/runuser -u "$1" -- ${activateStep} "$1"
                  ${pkgs.util-linux}/bin/runuser -u "$1" -- ${reloadStep} "$1"
                  ${updateStateStep} "$1"
                '';
              };
            }) users
          )
        else
          {
            "hjem-activate@" = {
              description = "Link files for %i from their manifest";
              enableStrictShellChecks = true;
              unitConfig.RequiresMountsFor = homeDirectories;
              serviceConfig = {
                User = "%i";
                Type = "oneshot";
              };
              requires = [ "hjem-prepare.service" ];
              after = [ "hjem-prepare.service" ];
              scriptArgs = "%i";
              script = ''exec ${activateStep} "$1"'';
            };

            "hjem-reload@" = {
              description = "Reload systemd user units for %i after Hjem file activation";
              enableStrictShellChecks = true;
              serviceConfig = {
                User = "%i";
                Type = "oneshot";
              };
              unitConfig.RequiresMountsFor = homeDirectories;
              requires = [ "hjem-activate@%i.service" ];
              after = [ "hjem-activate@%i.service" ];
              scriptArgs = "%i";
              script = ''exec ${reloadStep} "$1"'';
            };

            "hjem-update-state@" = {
              description = "Update Hjem state manifest for %i";
              enableStrictShellChecks = true;
              serviceConfig.Type = "oneshot";
              requires = [ "hjem-reload@%i.service" ];
              unitConfig.RequiresMountsFor = homeDirectories;
              after = [ "hjem-reload@%i.service" ];
              scriptArgs = "%i";
              script = ''exec ${updateStateStep} "$1"'';
            };
          }
      )
      // {
        hjem-cleanup = {
          description = "Cleanup disabled users' manifests";
          enableStrictShellChecks = true;
          serviceConfig.Type = "oneshot";
          after = [ "hjem.target" ];
          unitConfig.RefuseManualStart = false;
          script = ''
            ${lib.getExe (builtins.head users).cli} internal cleanup-state \
              --state-dir ${oldManifests} \
              ${lib.concatMapStringsSep " " (user: "--enabled-user ${lib.escapeShellArg user.user}") users}
          '';
        };
      };
    }
  );
}
