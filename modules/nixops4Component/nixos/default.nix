# SPDX-License-Identifier: MIT
#
# The module of the nixops4Component class, the class the nixops4
# integration evaluates components with, for a member that imports the
# NixOS resource module of nixops4-nixos
# (`nixops4-nixos.modules.nixops4Component.nixos`).
#
# That module declares the options a NixOS member is written with
# (`nixpkgs`, `nixos.module`, `nixos.specialArgs`, `ssh.*`,
# `copy.substituteOnDestination`, `sudo.enable`), evaluates
# `nixos.module` with `config.nixpkgs.lib.nixosSystem`, and takes the
# shell its deploy script runs in from its own nixpkgs. In caisson the
# member's `nixos.module` is a caisson NixOS configuration declared
# beneath the member, under the member's name, with
# `nixos.specialArgs` as its special arguments. This module declares
# it, makes `nixpkgs.lib.nixosSystem` return it in place of evaluating
# one, and takes the shell from the package set caisson selects for the
# member, for the system NixOps4 runs providers on. A member that does
# not import nixops4-nixos is not changed.
#
# The default module of the class selects this module.
{ ... }:
{
  config,
  lib,
  options,
  resourceProviderSystem,
  ...
}:
let
  manifest = lib.caisson-core.evalManifest;
  usesNixos = options ? nixos && options.nixos ? module;
  machine = lib.caisson.caisson-nixops4-resource.machineOf {
    context = "caisson's `nixos` module of the nixops4Component class";
    resource = manifest.name;
    declared = config.caisson.nixos.configurations;
  };
  bash = lib.getExe (lib.caisson.caisson-nixops4-resource.pkgsFor manifest resourceProviderSystem)
    .bash;
in
{
  _file = "caisson:nixops4Component/nixos";
  config = lib.optionalAttrs usesNixos {
    caisson.nixos.configurations.${manifest.name} = lib.caisson.nixos.mkConfiguration {
      configModule = config.nixos.module;
      specialArgs = config.nixos.specialArgs;
    };
    # nixops4-nixos builds `nixos.configuration` with this call.
    nixpkgs = lib.mkForce {
      lib.nixosSystem = _: machine.value;
    };
    inputs.executable = lib.mkForce bash;
  };
}
