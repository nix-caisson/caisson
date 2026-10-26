# SPDX-License-Identifier: MIT
#
# The NixOS adapter of the caisson-nixops4-resource class: it deploys
# the NixOS configuration declared beneath a resource, as
# nixops4-nixos deploys the NixOS configuration of its resource.
#
# When the resource holds a NixOS configuration, the adapter makes the
# resource an `exec` resource of NixOps4's `local` provider, unless the
# resource sets `type` itself. Its inputs copy the toplevel of the
# configuration to the host with `nix copy` and run its
# `bin/apply switch` over SSH. The SSH settings are the options
# nixops4-nixos declares, under the same names: `ssh.user`, `ssh.host`,
# `ssh.hostPublicKey`, `ssh.opts`, `copy.substituteOnDestination` and
# `sudo.enable`. The host defaults to the name of the resource. The
# shell that runs the script is `bash` from the package set caisson
# selects for the resource, for the system NixOps4 runs providers on.
#
# A resource holds one NixOS configuration to deploy, evaluated for one
# system; the adapter refuses more.
#
# The default module of the class selects this module. A resource that
# selects its modules itself lists it as
# `caisson/caisson-nixops4-resource/nixos` in a flake that lists caisson
# in `projects`.
{ ... }:
{
  config,
  lib,
  providers,
  resourceProviderSystem,
  ...
}:
let
  inherit (lib) mkOption types;
  manifest = lib.caisson-core.evalManifest;
  context = "caisson's NixOS adapter of the caisson-nixops4-resource class";
  declared = config.caisson.nixos.configurations;
  # Whether the resource holds a NixOS configuration. The names are
  # known in the childless view too, so a resource without one is left
  # alone there and in its full evaluation.
  holdsMachine = builtins.attrNames declared != [ ];
  # The NixOS configuration the resource deploys: the one declared
  # beneath it, evaluated for one system.
  nixos =
    (lib.caisson.caisson-nixops4.machineOf {
      inherit context declared;
      resource = manifest.name;
    }).value;
  target = (if config.ssh.user == null then "" else "${config.ssh.user}@") + config.ssh.host;
  # The host key is the only key the SSH client accepts for the host,
  # as nixops4-nixos has it.
  knownHosts = builtins.toFile "known_hosts" ''
    ${config.ssh.host} ${config.ssh.hostPublicKey}
  '';
  src = lib.caisson.caisson-nixops4.ecosystemSrcOf {
    explicit = null;
    inherit manifest;
  };
  bash = lib.getExe (lib.caisson.caisson-nixops4.pkgsFor manifest resourceProviderSystem).bash;
in
{
  _file = "caisson:caisson-nixops4-resource/nixos";
  options = {
    nixos.configuration = mkOption {
      type = types.raw;
      readOnly = true;
      description = ''
        The NixOS configuration this resource deploys: the one declared
        beneath it, as caisson evaluated it.
      '';
    };
    ssh.user = mkOption {
      type = types.nullOr types.str;
      default = "root";
      description = ''
        The user name of the SSH connection. When `null`, the SSH client
        chooses it from its configuration.
      '';
    };
    ssh.host = mkOption {
      type = types.str;
      default = manifest.name;
      defaultText = lib.literalMD "the name of the resource";
      description = "The host the SSH client connects to.";
    };
    ssh.hostPublicKey = mkOption {
      type = types.str;
      description = ''
        The public key of the host. It is the only key the SSH client
        accepts for the host.
      '';
    };
    ssh.opts = mkOption {
      type = types.str;
      default = "";
      description = "Further options of the SSH client, as one shell word.";
    };
    copy.substituteOnDestination = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether the host tries its substituters for the paths it receives
        before they are copied to it.
      '';
    };
    sudo.enable = mkOption {
      type = types.bool;
      default = config.ssh.user != "root";
      defaultText = lib.literalMD ''`false` iff `ssh.user` is `"root"`'';
      description = "Whether the configuration is applied with `sudo`.";
    };
  };
  config = lib.mkIf holdsMachine {
    # NixOps4's `local` provider, whose `exec` type deploys the
    # configuration. A resource that declares `providers.local` or sets
    # `type` replaces them.
    providers.local = lib.mkDefault src.modules.nixops4Provider.local;
    type = lib.mkDefault providers.local.exec;
    nixos.configuration = nixos;
    inputs = {
      executable = bash;
      args = [
        "-c"
        # ConnectTimeout and ConnectionAttempts keep a host that is not
        # up from hanging the deployment. Password and
        # keyboard-interactive authentication are off because stdin is
        # not connected. StrictHostKeyChecking with the configured key
        # alone refuses a host the configuration does not name.
        ''
          set -euo pipefail
          export NIX_SSHOPTS="-o ConnectTimeout=10 -o ConnectionAttempts=12 -o KbdInteractiveAuthentication=no -o PasswordAuthentication=no -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${knownHosts} "${lib.escapeShellArg config.ssh.opts}
          nix copy --to "ssh-ng://$0" "$1" --no-check-sigs --extra-experimental-features nix-command${lib.optionalString config.copy.substituteOnDestination " --substitute-on-destination"}
          ssh $NIX_SSHOPTS "$0" "${lib.optionalString config.sudo.enable "sudo "}$1/bin/apply switch"
        ''
        target
        nixos.config.system.build.toplevel
      ];
    };
  };
}
