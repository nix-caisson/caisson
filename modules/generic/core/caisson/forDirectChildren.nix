# SPDX-License-Identifier: MIT
#
# What this configuration gives the configurations of a class declared
# directly beneath it: additions to the default selection of that
# class, and whether they read the full evaluation of this
# configuration. A configuration evaluated per system and declared here
# is a direct child, since a system is no level of its own. Nothing
# here passes through a configuration of another class, and the
# configurations beneath a direct child do not get it. It is read from
# the childless view, which the configurations beneath are built
# against.
{ lib, ... }:
{
  options.caisson.forDirectChildren = {

    extraDefaultModuleImports = lib.mkOption {
      type = lib.types.attrsOf (lib.types.functionTo (lib.types.listOf lib.types.raw));
      default = { };
      example = lib.literalExpression ''
        {
          nixos = lib: [ lib.caisson.modules.nixos.site-base ];
        }
      '';
      description = ''
        Additions to the default selection of a class for the
        configurations of that class declared directly beneath this
        configuration: by class, a function of the lib of such a
        configuration returning registered modules. A direct child that
        passes no `moduleImports` gets every entry named `default`, then
        the additions of `caisson.forChildren.extraDefaultModuleImports`
        of the levels above it, then those of
        `caisson.forNearestChildren.extraDefaultModuleImports`, then
        these. Definitions from several modules are concatenated.

        A module listed here is a module registered in the
        composition, on `mkLib` or by a project.
      '';
    };

    unsafeCrossChildReferences = lib.mkOption {
      type = lib.types.attrsOf lib.types.bool;
      default = { };
      example = {
        caisson-nixops4-resource = true;
      };
      description = ''
        By class, whether the configurations of that class declared
        directly beneath this configuration read the full evaluation
        of this configuration, with its children, in place of its
        childless view (`lib.caisson-core.evalManifest.crossChildLevel`).
        They can then reach every configuration beneath this one, and
        a loop between them is a Nix infinite recursion, which the
        childless view otherwise rules out.

        This setting beats one through `caisson.forNearestChildren` or
        `caisson.forChildren`.
      '';
    };

  };
}
