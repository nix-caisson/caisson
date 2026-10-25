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
# and restart which guests, through a polkit rule. The users listed for
# a guest on cloud-hypervisor that has a vsock CID may also connect to
# the Unix socket of its hybrid vsock.
#
# The guests are read in the evaluation of the host that holds them.
# In the evaluation without the configurations declared inside it,
# which the guests read, the host has no guests.
{ ... }:
{
  config,
  lib,
  pkgs,
  ...
}:
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
            # The Unix socket through which the host reaches the guest's
            # vsock, from the guest's own evaluation, null for a guest
            # that has no vsock CID or is not on cloud-hypervisor.
            vsockSocket =
              if entry.manifest.value.config.microvm.vsock.cid == null then
                null
              else
                lib.caisson.caisson-microvm.vsockSocketOf {
                  inherit (entry.manifest.value.config.microvm) hypervisor;
                  inherit (config.microvm) stateDir;
                  name = nameOf entry;
                };
          };
        }) entries
      );

  # The guests that have a runtime limit, by name.
  limited = lib.filterAttrs (_name: guest: guest.start.runtimeMaxSec != null) guests;

  operators = config.caisson.microvm-host.operators;

  # The units each operator may start, stop and restart.
  unitsByUser = builtins.mapAttrs (_user: builtins.map (guest: "microvm@${guest}.service")) operators;

  # The users that `caisson.microvm-host.operators` lists for the guest
  # `name`.
  operatorsOf =
    name: builtins.filter (user: builtins.elem name operators.${user}) (builtins.attrNames operators);

  # The guests whose vsock the host reaches through a Unix socket and
  # that have operators, by name. The operators of such a guest may
  # connect to its socket.
  reachable = lib.filterAttrs (
    name: guest: guest.vsockSocket != null && operatorsOf name != [ ]
  ) guests;

  # The group of the operators of the guest `name`. Each guest has a
  # group of its own, so an operator of one guest cannot connect to the
  # socket of another.
  groupOf = name: "microvm-${name}";

  # The step that lets the operators of the guest `name` connect to its
  # socket. systemd runs it as root after each start of the unit of the
  # guest. microvm.nix gives the unit of a guest that has a vsock CID the
  # type `notify`, so the step runs once the guest reports that it is
  # ready, and the socket exists by then. A unit of another type runs the
  # step as soon as cloud-hypervisor is started, so the step waits for
  # the socket for up to 30 seconds. It then gives the socket the group
  # of the operators of the guest and the mode 0660. The step fails when
  # the socket does not appear in that time, and then systemd stops the
  # unit of the guest.
  socketAccessOf =
    name: guest:
    pkgs.writeShellScript "microvm-vsock-access-${name}" ''
      socket=${lib.escapeShellArg guest.vsockSocket}
      for _ in $(${lib.getExe' pkgs.coreutils "seq"} 300); do
        if [ -S "$socket" ]; then
          ${lib.getExe' pkgs.coreutils "chgrp"} ${groupOf name} "$socket"
          ${lib.getExe' pkgs.coreutils "chmod"} 0660 "$socket"
          exit 0
        fi
        ${lib.getExe' pkgs.coreutils "sleep"} 0.1
      done
      echo "cloud-hypervisor did not create $socket within 30 seconds." >&2
      exit 1
    '';

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

      A guest on cloud-hypervisor that has a vsock CID has a hybrid vsock,
      the Unix socket `notify.vsock` in its working directory
      `<microvm.stateDir>/<guest>`. Such a guest gets the group
      `microvm-<guest>`, whose members are the users listed for it. The
      working directory of the guest belongs to that group with the mode
      0750, and the socket belongs to it with the mode 0660 after each
      start of the guest. So the users listed for the guest can connect to
      its socket, and no other user except root can. A client connects to
      the socket, sends `CONNECT <port>` and a newline, reads `OK <n>` and
      a newline, and then speaks to the vsock port of the guest. A guest
      on any other hypervisor has the kernel's vsock and gets no group.
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
    #
    # cloud-hypervisor runs as the user `microvm` and creates the socket
    # of a guest with the group `kvm`. Before each start of the unit
    # `microvm@<guest>.service` of a guest that has operators, root
    # removes a socket that a previous run left, so the step after the
    # start finds the socket of this run. After each start, root gives the
    # socket the group of the operators of the guest and the mode 0660.
    systemd.services = lib.mkMerge (
      lib.mapAttrsToList (name: guest: {
        "microvm@${name}".serviceConfig = {
          ExecStartPre = [
            "+${lib.getExe' pkgs.coreutils "rm"} -f ${lib.escapeShellArg guest.vsockSocket}"
          ];
          ExecStartPost = [ "+${socketAccessOf name guest}" ];
        };
      }) reachable
      ++ lib.mapAttrsToList (name: _guest: {
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

    # The operators of a guest on cloud-hypervisor that has a vsock CID
    # connect to the socket `notify.vsock` of that guest. Each such guest
    # has the group `microvm-<guest>`, whose members are its operators.
    users.groups = lib.mapAttrs' (name: _guest: {
      name = groupOf name;
      value.members = operatorsOf name;
    }) reachable;

    # The working directory of such a guest belongs to the group of its
    # operators, with the mode 0750, so the operators reach the socket in
    # it. microvm.nix creates the directory owned by the user `microvm`
    # and the group `kvm`, with the mode 0775. Every program of
    # microvm.nix that writes in the directory runs as the user
    # `microvm` or as root. The group gets no write access, because the
    # host runs programs from the directory as root.
    systemd.tmpfiles.settings."10-microvm" = lib.mapAttrs' (name: _guest: {
      name = "${config.microvm.stateDir}/${name}";
      value.d = {
        group = lib.mkForce (groupOf name);
        mode = lib.mkForce "0750";
      };
    }) reachable;

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
