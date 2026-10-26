# SPDX-License-Identifier: MIT
#
# What this configuration gives the nearest configurations of a class
# beneath it: additions to the default selection of that class. An
# addition for a class passes through the configurations of other
# classes beneath this one, such as a structural group or a disk
# layout, and reaches the first configurations of its class on each
# path down. The configurations beneath those do not get it. This
# configuration is not among those it is given to. The additions are
# read from the childless view, which the configurations beneath are
# built against.
{ lib, ... }:
{
  options.caisson.forNearestChildren = {

    extraDefaultModuleImports = lib.mkOption {
      type = lib.types.attrsOf (lib.types.functionTo (lib.types.listOf lib.types.raw));
      default = { };
      example = lib.literalExpression ''
        {
          nixos = lib: [ lib.caisson.modules.nixos.colmena-deployment ];
        }
      '';
      description = ''
        Additions to the default selection of a class for the nearest
        configurations of that class beneath this configuration: by
        class, a function of the lib of such a configuration returning
        registered modules. A configuration of the class is a nearest
        one when no other configuration of the class sits between it
        and this configuration. Configurations of other classes and
        systems between the two do not count.

        A nearest configuration that passes no `moduleImports` gets
        every entry named `default`, then the additions of
        `caisson.forChildren.extraDefaultModuleImports` of the levels
        above it, then these, those of the levels above first. A
        configuration declared inside a nearest configuration does not
        get them. A configuration that passes `moduleImports` selects
        its modules itself and gets none of them. Definitions from
        several modules are concatenated.

        Use this option for what the nearest configurations of a class
        live on, such as the deployment of a node or the disk layout of
        a machine, and `caisson.forChildren.extraDefaultModuleImports`
        for what applies at any depth.

        A module listed here is a module registered in the
        composition, on `mkLib` or by a project.
      '';
    };

    unsafeCrossChildReferences = lib.mkOption {
      type = lib.types.attrsOf lib.types.bool;
      default = { };
      example = {
        nixos = true;
      };
      description = ''
        By class, whether the nearest configurations of that class
        beneath this configuration read the full evaluation of this
        configuration, with its children, in place of the childless
        view of their parent (`lib.caisson-core.evalManifest.crossChildLevel`).
        It passes through configurations of other classes, as the
        additions above do, so a machine inside a structural group or a
        disk layout beneath this configuration is reached. A
        configuration it reaches can read every configuration beneath
        this one, and a loop between them is a Nix infinite recursion,
        which the childless view otherwise rules out.

        A setting through `caisson.forDirectChildren` beats this one,
        which beats one through `caisson.forChildren`, and within one
        container the nearest parent that sets it wins. This setting
        connects at the nearest configurations of its class whether or
        not it wins there.
      '';
    };

  };
}
