# SPDX-License-Identifier: MIT
#
# The guest `probe` of the microvm host test. It sets its own
# `microvm.*` options: it runs on cloud-hypervisor with one virtual
# CPU, 512 megabytes and the vsock CID 10. It answers on its vsock port
# 5000 with what it reads there.
{ ... }:
{ lib, pkgs, ... }:
{
  system.stateVersion = "25.05";

  microvm = {
    hypervisor = "cloud-hypervisor";
    vcpu = 1;
    mem = 512;
    vsock.cid = 10;
  };

  systemd.services.echo = {
    description = "Echo on vsock port 5000";
    wantedBy = [ "multi-user.target" ];
    serviceConfig.ExecStart = "${lib.getExe pkgs.socat} VSOCK-LISTEN:5000,fork,reuseaddr EXEC:${lib.getExe' pkgs.coreutils "cat"}";
  };
}
