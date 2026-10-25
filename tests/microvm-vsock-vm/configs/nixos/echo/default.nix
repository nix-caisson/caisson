# SPDX-License-Identifier: MIT
#
# The guest kind `echo` of the microvm vsock test: the NixOS
# configuration each slot of the kind takes. The guest answers on its
# vsock port 5000 with what it reads there.
{ ... }:
{ lib, pkgs, ... }:
{
  system.stateVersion = "25.05";

  systemd.services.echo = {
    description = "Echo on vsock port 5000";
    wantedBy = [ "multi-user.target" ];
    serviceConfig.ExecStart = "${lib.getExe pkgs.socat} VSOCK-LISTEN:5000,fork,reuseaddr EXEC:${lib.getExe' pkgs.coreutils "cat"}";
  };
}
