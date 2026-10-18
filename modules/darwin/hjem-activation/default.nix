# SPDX-License-Identifier: MIT
#
# A darwin module with which a macOS machine activates the hjem
# configurations declared inside it.
#
# Activating a hjem configuration means applying its manifest with
# hjem's CLI. hjem has a nix-darwin module that does this for the users
# it embeds, with a launchd agent, `org.hjem.activate`, that applies the
# manifest of the user it runs for and keeps the state in
# `~/Library/Application Support/Hjem`, and restarts the agent of each
# user from the machine's activation script, with `launchctl
# kickstart`. caisson does not use that nix-darwin module, and this
# module writes the same agent, script and restart.
#
# hjem's nix-darwin module declares the agent in `launchd.user.agents`,
# which nix-darwin installs for `system.primaryUser` alone. This module
# declares it in `launchd.agents`, which nix-darwin installs in
# `/Library/LaunchAgents`, where launchd loads it for every user who
# logs in, so each hjem user gets the agent, and the machine needs no
# primary user for it. The agent exits for a user no hjem configuration
# here names.
#
# The module also writes hjem's second agent, `org.nix.link-nix-apps`,
# which links the applications of the packages of the user into
# `~/Applications/Nix User Apps`, adds each user's `packages` to
# `users.users.<user>.packages`, and keeps each user's
# `extraDependencies` in the system, in `/etc/hjem/extra-dependencies`,
# as hjem's nix-darwin module does.
#
# Which configurations: the enabled hjem configurations this darwin
# configuration passes up, leaving out those declared inside a machine
# that is itself inside this one, and those evaluated for another
# system. caisson's `default` darwin module imports this module.
#
# The module reads the hjem configurations from the full evaluation of
# the darwin configuration; in the childless evaluation it defines
# nothing.
{ closure-lib, ... }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.caisson) evalManifest;

  isActivatedHere =
    entry:
    entry.manifest.type == "hjem"
    && !(builtins.any (segment: segment.type == "nixos" || segment.type == "darwin") (
      lib.lists.init entry.path
    ))
    && entry.manifest.system == evalManifest.system;

  users =
    builtins.map
      (entry: {
        inherit (entry.manifest.value.config) user packages extraDependencies;
        inherit (entry.manifest.outputs) manifestFile cli;
      })
      (
        builtins.filter (entry: isActivatedHere entry && entry.manifest.value.config.enable) (
          config.caisson.exports.configurations
        )
      );

  newManifests = pkgs.linkFarm "hjem-manifests" (
    builtins.map (user: {
      name = "manifest-${user.user}.json";
      path = user.manifestFile;
    }) users
  );

  # The prefix hjem's CLI gives the backup of a file it replaces, the
  # default of hjem's nix-darwin module.
  prefix = ".backup-";

  # The agent sets `hjem` to the CLI of the configuration of the user it
  # runs for, and exits for any other user.
  selectUser = ''
    case "$USER" in
      ${lib.concatMapStrings (user: ''
        ${lib.escapeShellArg user.user}) hjem=${lib.getExe user.cli} ;;
      '') users}
      *) exit 0 ;;
    esac
  '';

  # The start of the applications agent, which runs no hjem CLI: it
  # exits for a user no hjem configuration here names.
  requireUser = ''
    case "$USER" in
      ${lib.concatMapStringsSep " | " (user: lib.escapeShellArg user.user) users}) ;;
      *) exit 0 ;;
    esac
  '';

  activateLabel = "org.hjem.activate";
  appsLabel = "org.nix.link-nix-apps";

  # The activation step that restarts an agent of each user who has a
  # session, as hjem's nix-darwin module does.
  kick =
    label:
    lib.concatMapStringsSep "\n" (user: ''
      if uid="$(${lib.getExe' pkgs.coreutils-full "id"} -u ${lib.escapeShellArg user.user} 2>/dev/null)"; then
        /bin/launchctl kickstart -k "gui/''${uid}/${label}" 2>/dev/null || true
      fi
    '') users;

  names = builtins.map (user: user.user) users;
  repeated = lib.lists.unique (
    builtins.filter (name: lib.lists.count (other: other == name) names > 1) names
  );
in
{
  # The module reads `config.caisson.exports.configurations`. The core
  # module declares that option.
  imports = [ closure-lib.caisson.modules.darwin.core ];

  config = lib.mkIf (!evalManifest.childless && users != [ ]) {
    assertions = [
      {
        assertion = repeated == [ ];
        message = "caisson: this darwin configuration activates more than one hjem configuration for ${lib.concatStringsSep ", " repeated}.";
      }
    ];

    users.users = builtins.listToAttrs (
      builtins.map (user: {
        name = user.user;
        value.packages = user.packages;
      }) users
    );

    # nix-darwin has no `system.extraDependencies`; hjem's nix-darwin
    # module keeps the dependencies in the system this way.
    environment.etc."hjem/extra-dependencies".text = lib.concatLines (
      builtins.concatMap (user: builtins.map (path: "${path}") user.extraDependencies) users
    );

    launchd.agents = {
      hjem-activate.serviceConfig = {
        Program = lib.getExe (
          pkgs.writeShellApplication {
            name = "hjem-activate";
            runtimeInputs = [ pkgs.coreutils-full ];
            text = ''
              set -euo pipefail

              USER="$(id -un)"
              ${selectUser}
              NEW="${newManifests}/manifest-''${USER}.json"

              if [ ! -f "$NEW" ]; then
                exit 0
              fi

              STATE_DIR="$HOME/Library/Application Support/Hjem"
              mkdir -p "$STATE_DIR"
              CUR="$STATE_DIR/manifest.json"

              "$hjem" internal activate \
                --manifest "$NEW" \
                --state "$CUR" \
                --actions-file "$STATE_DIR/actions.json" \
                --prefix "${prefix}"
            '';
          }
        );
        Label = activateLabel;
        RunAtLoad = true;
        StandardOutPath = "/var/tmp/hjem-activate.out";
        StandardErrorPath = "/var/tmp/hjem-activate.err";
      };

      link-nix-apps.serviceConfig = {
        Program = lib.getExe (
          pkgs.writeShellApplication {
            name = "link-nix-apps";
            runtimeInputs = with pkgs; [
              coreutils-full
              findutils
              gnugrep
              nix
            ];
            text = ''
              set -euo pipefail

              USER="$(id -un)"
              ${requireUser}
              GROUP="$(id -gn)"
              DEST="$HOME/Applications/Nix User Apps"
              PROFILE="/etc/profiles/per-user/$USER"

              install -d -m 0755 -o "$USER" -g "$GROUP" "$DEST"

              desired="$(mktemp -t desired-apps.XXXXXX)"
              trap 'rm -f "$desired"' EXIT

              nix-store -qR "$PROFILE" | while IFS= read -r p; do
                apps="$p/Applications"
                if [ -d "$apps" ]; then
                  find "$apps" -maxdepth 1 -type d -name "*.app" -print0 \
                  | while IFS= read -r -d "" app; do
                      bname="$(basename "$app")"
                      echo "$bname" >> "$desired"
                      ln -sfn "$app" "$DEST/$bname"
                    done
                fi
              done

              sort -u "$desired" -o "$desired"

              find "$DEST" -maxdepth 1 -type l -name "*.app" -print0 \
              | while IFS= read -r -d "" link; do
                  name="$(basename "$link")"
                  if ! grep -Fxq "$name" "$desired"; then
                    rm -f "$link"
                  fi
                done

              # Remove broken links
              find "$DEST" -maxdepth 1 -type l -name "*.app" -print0 \
                | xargs -0 -I {} bash -c '[[ -e "{}" ]] || rm -f "{}"'
            '';
          }
        );
        Label = appsLabel;
        RunAtLoad = true;
        StandardOutPath = "/var/tmp/link-nix-apps.out";
        StandardErrorPath = "/var/tmp/link-nix-apps.err";
      };
    };

    # The restart runs in `postActivation`, after nix-darwin's `launchd`
    # step installs the agents of the new generation. nix-darwin runs a
    # fixed list of activation steps; hjem's nix-darwin module restarts
    # the activation agent from a step of another name, which nix-darwin
    # does not run, and the applications agent from `applications`,
    # which runs before the agents are installed.
    system.activationScripts.postActivation.text = lib.mkAfter ''
      ${kick activateLabel}
      ${kick appsLabel}
    '';
  };
}
