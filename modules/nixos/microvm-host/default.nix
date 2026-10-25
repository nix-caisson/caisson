# SPDX-License-Identifier: MIT
#
# A NixOS module for a host that runs microvm.nix guests declared
# inside it. A host selects it by name, as `microvm-host`, or as
# `caisson/microvm-host` in a flake that lists caisson in `projects`.
#
# It imports microvm.nix's host module and defines
# `microvm.vms.<guest>` for every guest that belongs to the host. The
# guests are the NixOS configurations declared inside the host's
# caisson-microvm configurations and the host's microvm
# configurations. A guest belongs to the host when no other NixOS
# configuration or microvm configuration sits between the two
# (`lib.caisson.integrations.belongsHere`), so a guest declared inside
# a guest belongs to that guest. Each guest is read from the
# configurations the host passes up, so the host's
# `caisson.<integration>.exported` selectors decide which guests it
# runs. A guest is named in `microvm.vms` after the name it is
# declared under.
#
# For each guest, `evaluatedConfig` is caisson's evaluation of the
# guest, the configuration published as `nixosConfigurations.<guest>`.
# A guest of a caisson-microvm configuration gets `autostart` and
# `restartIfChanged` from that configuration. When that configuration
# sets `runtimeMaxSec`, the guest gets the timer
# `microvm-runtime-limit-<guest>.timer`, which each start of its unit
# `microvm@<guest>.service` arms. When that many seconds have passed,
# the timer's service stops the unit. A microvm configuration keeps the
# default `autostart` of microvm.nix and gets `restartIfChanged`
# true. These are at `mkDefault` priority, so a host module that sets
# them replaces them. The host refuses microvm.nix's `config` and
# `flake` forms for these names, since each evaluates the guest a
# second way.
#
# `caisson.microvm-host.operators` names the users that may start, stop
# and restart which guests, through a polkit rule.
#
# The guests are read in the evaluation of the host that holds them.
# In the evaluation without the configurations declared inside it,
# which the guests read, the host has no guests.
{ ... }:
{ config, lib, ... }:
let
  manifest = lib.caisson-core.evalManifest;
  integrations = lib.caisson.integrations;

  src =
    let
      found = lib.caisson-core.ecosystemSrc "microvm";
    in
    if found == null then
      throw ''
        caisson's `microvm-host` NixOS module needs the microvm.nix source.
        Declare `defaultEcosystemSrc.microvm` in the mkLib call, or pin a
        source named `microvm` in the `sources` passed to mkLib.
      ''
    else
      lib.caisson.caisson-microvm.assertMicrovmEcosystemSrc "caisson's `microvm-host` NixOS module" found;

  # Whether a configuration passed up through the host is a guest of
  # the host, evaluated for the system of the host.
  isGuest =
    entry:
    let
      type = entry.manifest.type or null;
    in
    entry.attrset == "nixosConfigurations"
    && (entry.system or null) == (manifest.system or null)
    && integrations.belongsHere "nixos" entry
    && integrations.belongsHere "microvm" entry
    && (
      type == "microvm"
      || (
        type == "nixos" && builtins.any (segment: segment.type == "caisson-microvm") (lib.init entry.path)
      )
    );

  # How the host starts and stops a guest.
  startOf =
    entry:
    if entry.manifest.type == "microvm" then
      {
        autostart = null;
        restartIfChanged = true;
        runtimeMaxSec = null;
      }
    else
      entry.manifest.nearest.caisson-microvm.outputs.start;

  entries =
    if manifest == null || manifest.childless then
      [ ]
    else
      builtins.filter isGuest config.caisson.exports.configurations;

  nameOf = entry: (lib.last entry.namePath).name;

  names = builtins.map nameOf entries;

  repeated = builtins.filter (
    name: builtins.length (builtins.filter (other: other == name) names) > 1
  ) (lib.unique names);

  # The guests of the host, by name.
  guests =
    if repeated != [ ] then
      throw ''
        caisson's `microvm-host` NixOS module names each guest after the name it is
        declared under, and several guests of this host are declared as
        ${lib.concatMapStringsSep ", " (name: "`${name}`") repeated}.
      ''
    else
      builtins.listToAttrs (
        builtins.map (entry: {
          name = nameOf entry;
          value = {
            inherit (entry.manifest) value;
            start = startOf entry;
          };
        }) entries
      );

  # The guests that have a runtime limit, by name.
  limited = lib.filterAttrs (_name: guest: guest.start.runtimeMaxSec != null) guests;

  operators = config.caisson.microvm-host.operators;

  # The units each operator may start, stop and restart.
  unitsByUser = builtins.mapAttrs (_user: builtins.map (guest: "microvm@${guest}.service")) operators;

  unknownOperated = lib.unique (
    builtins.filter (guest: !(guests ? ${guest})) (builtins.concatLists (builtins.attrValues operators))
  );
in
{
  _file = "caisson:microvm-host";

  imports = [ "${src}/nixos-modules/host" ];

  options.caisson.microvm-host.operators = lib.mkOption {
    type = lib.types.attrsOf (lib.types.listOf lib.types.str);
    default = { };
    example = {
      chris = [
        "rea-1"
        "rea-2"
      ];
    };
    description = ''
      The users that may start, stop and restart guests of this host, by
      user name, each with the names of the guests that user may control.
      A polkit rule lets each user run `systemctl start`, `systemctl stop`
      and `systemctl restart` on the unit `microvm@<guest>.service` of each
      guest listed for that user, and on no other unit. Every name listed is
      a guest of this host, and a name that is not is refused.
    '';
  };

  config = {
    microvm.vms = builtins.mapAttrs (
      _name: guest:
      {
        evaluatedConfig = guest.value;
        restartIfChanged = lib.mkDefault guest.start.restartIfChanged;
      }
      // (
        if guest.start.autostart == null then { } else { autostart = lib.mkDefault guest.start.autostart; }
      )
    ) guests;

    # The runtime limit of a guest. The unit `microvm@<guest>.service`
    # wants the timer `microvm-runtime-limit-<guest>.timer`, so each
    # start of the guest's unit starts the timer and arms it afresh. The
    # timer is bound to the guest's unit, so stopping the guest stops the
    # timer. When the timer elapses, its service runs a stop job on the
    # guest's unit. microvm.nix gives that unit `Restart=always`, and
    # systemd does not restart a unit that a stop job stopped.
    systemd.services = lib.mkMerge (
      lib.mapAttrsToList (name: _guest: {
        "microvm@${name}".wants = [ "microvm-runtime-limit-${name}.timer" ];
        "microvm-runtime-limit-${name}" = {
          description = "Stop the microvm guest ${name} at its runtime limit";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe' config.systemd.package "systemctl"} stop microvm@${name}.service";
          };
        };
      }) limited
    );

    systemd.timers = lib.mapAttrs' (name: guest: {
      name = "microvm-runtime-limit-${name}";
      value = {
        description = "Runtime limit of the microvm guest ${name}";
        bindsTo = [ "microvm@${name}.service" ];
        after = [ "microvm@${name}.service" ];
        timerConfig.OnActiveSec = "${toString guest.start.runtimeMaxSec}s";
      };
    }) limited;

    assertions =
      builtins.concatMap (name: [
        {
          assertion = config.microvm.vms.${name}.config == null && config.microvm.vms.${name}.flake == null;
          message = ''
            The guest `${name}` of this host is a configuration declared inside it, and
            caisson's `microvm-host` NixOS module gives microvm.nix its evaluation as
            `microvm.vms.${name}.evaluatedConfig`. Leave `microvm.vms.${name}.config`
            and `microvm.vms.${name}.flake` unset.
          '';
        }
      ]) (builtins.attrNames guests)
      ++ lib.optional (manifest != null && !manifest.childless) {
        assertion = unknownOperated == [ ];
        message = ''
          `caisson.microvm-host.operators` lists ${
            lib.concatMapStringsSep ", " (name: "`${name}`") unknownOperated
          }, which no guest of this host is declared as. The guests of this host are
          ${
            if guests == { } then
              "none"
            else
              lib.concatMapStringsSep ", " (name: "`${name}`") (builtins.attrNames guests)
          }.
        '';
      };

    security.polkit.enable = lib.mkIf (operators != { }) true;
    security.polkit.extraConfig = lib.mkIf (operators != { }) ''
      // caisson's `microvm-host` NixOS module: the guests each user may start,
      // stop and restart.
      polkit.addRule(function (action, subject) {
        var units = ${builtins.toJSON unitsByUser};
        if (action.id == "org.freedesktop.systemd1.manage-units" && units.hasOwnProperty(subject.user)) {
          var verb = action.lookup("verb");
          if ((verb == "start" || verb == "stop" || verb == "restart") && units[subject.user].indexOf(action.lookup("unit")) >= 0) {
            return polkit.Result.YES;
          }
        }
      });
    '';
  };
}
