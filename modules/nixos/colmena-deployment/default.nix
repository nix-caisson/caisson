# SPDX-License-Identifier: MIT
#
# A NixOS module for a NixOS configuration that colmena deploys. It
# declares colmena's `deployment` options, the settings of a node that
# colmena reads: its address, its tags and the keys its services need.
# It also imports colmena's modules that act on those settings: the
# assertions on them and the services that install the keys.
#
# The default module of the colmena class adds this module to every
# NixOS configuration declared inside a colmena configuration. A NixOS
# configuration that is also deployed some other way, and sets these
# options, imports this module itself.
#
# colmena's `deploymentOptions` takes the node's name as a module
# argument, and `deployment.targetHost` defaults to it. A NixOS
# configuration has no such argument, so this module passes `null`.
# The colmena integration fills a `targetHost` left at `null` with the
# node's name when it builds the hive, where the name is known.
#
# The colmena source is the one the composition declares or pins under
# the name `colmena`, read from the library of the evaluation, so these
# options match the colmena whose command deploys the node.
{ ... }:
{ lib, ... }:
let
  src =
    let
      found = lib.caisson-core.ecosystemSrc "colmena";
    in
    if found == null then
      throw ''
        caisson's `colmena-deployment` NixOS module needs the colmena source.
        Declare `defaultEcosystemSrc.colmena` in the mkLib call, or pin a
        source named `colmena` in the `sources` passed to mkLib.
      ''
    else
      found;

  upstream = src.nixosModules.deploymentOptions;

  # `deploymentOptions` with `name` passed as `null`. The module system
  # passes a module the arguments its pattern names, so the wrapper has
  # the pattern of upstream's module without `name`.
  deploymentOptions = lib.setFunctionArgs (args: upstream (args // { name = null; })) (
    builtins.removeAttrs (lib.functionArgs upstream) [ "name" ]
  );
in
{
  _file = "caisson:colmena-deployment";
  imports = [
    deploymentOptions
    src.nixosModules.assertionModule
    src.nixosModules.keyChownModule
    src.nixosModules.keyServiceModule
  ];
}
