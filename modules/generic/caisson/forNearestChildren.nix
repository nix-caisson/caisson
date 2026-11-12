# SPDX-License-Identifier: MIT
#
# What this configuration gives the nearest configurations of a class
# declared inside it: additions to the default selection of that class.
# An addition for a class passes through the configurations of other
# classes declared inside this configuration, such as a structural
# group or a disk layout, and is given to the first configurations of
# its class on each path down. The configurations declared inside those
# do not get it. This configuration is not among those it is given to.
# The additions are read from the result of the childless evaluation,
# which the configurations declared inside it are built against.
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
        configurations of that class declared inside this configuration: by
        class, a function of the lib of such a configuration returning
        registered modules. A configuration of the class is a nearest
        configuration when no other configuration of the class sits between it
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
        a NixOS configuration, and `caisson.forChildren.extraDefaultModuleImports`
        for what applies to the configurations of the class at every
        level inside this configuration.

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
        declared inside this configuration read the result of the full
        evaluation of this configuration, with its children, in place of
        the result of the childless evaluation of their parent
        (`lib.caisson-core.evalManifest.crossChildLevel`). It passes
        through configurations of other classes, as the additions above
        do, so it applies to a NixOS configuration inside a structural
        group or a disk layout declared inside this configuration. A
        configuration it applies to can read any configuration declared
        inside this configuration, and a loop between them is a Nix
        infinite recursion, which the childless evaluation otherwise
        rules out.

        A setting through `caisson.forDirectChildren` beats a setting
        here, which beats a setting through `caisson.forChildren`, and within one
        container the nearest parent that sets it wins. This setting
        connects at the nearest configurations of its class whether or
        not it wins there.
      '';
    };

  };
}
