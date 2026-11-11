# SPDX-License-Identifier: MIT
#
# What this configuration gives the configurations declared inside it,
# nested configurations included: additions to the default selection of
# a class, which a configuration gets when it passes no `moduleImports`;
# a default package set, which a configuration runs on when neither it
# nor a configuration between selects another; and the systems that
# configurations evaluated per system are evaluated for. This
# configuration is not among those they are given to. They are read
# from the childless view, which the configurations declared inside it
# are built against.
{ lib, ... }:
{
  options.caisson.forChildren = {

    extraDefaultModuleImports = lib.mkOption {
      type = lib.types.attrsOf (lib.types.functionTo (lib.types.listOf lib.types.raw));
      default = { };
      example = lib.literalExpression ''
        {
          nixos = lib: [ lib.caisson.modules.nixos.gaming ];
        }
      '';
      description = ''
        Additions to the default selection of a class for the
        configurations declared inside this configuration: by class, a
        function of the lib of such a configuration returning
        registered modules. A configuration that passes no
        `moduleImports` gets every entry named `default` followed by
        these, those of the levels above it first. A configuration
        that passes `moduleImports` selects its modules itself and
        gets none of them. Definitions from several modules are
        concatenated.

        A configuration of the class gets these additions however many
        configurations lie between it and this configuration.
        `caisson.forNearestChildren.extraDefaultModuleImports` gives
        additions to the nearest configurations of a class alone.

        A module listed here is a module registered in the
        composition, on `mkLib` or by a project.
      '';
    };

    defaultPkgs = lib.mkOption {
      type = lib.types.nullOr (lib.types.functionTo lib.types.raw);
      default = null;
      example = lib.literalExpression "pkgSets: pkgSets.stable";
      description = ''
        The package set the configurations declared inside this
        configuration get by default: a function that receives the
        package sets available to such a configuration, as an attribute
        set by package config name, and returns the set to run on. A
        configuration declared inside runs on it unless that
        configuration, or a configuration between the two, is
        constructed with `defaultPkgs` or sets this option. This
        configuration runs on the set it was constructed with. When
        null, the configurations declared inside get the package set
        selection that applies to this configuration.
      '';
    };

    systems = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      example = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      description = ''
        The systems the configurations declared inside this
        configuration are evaluated for. It applies to configurations that are
        evaluated per system, such as a NixOS configuration or a
        home-manager configuration: each gets one evaluation per
        system listed.

        When null, a configuration that is itself evaluated per
        system has its children evaluated for its system only, so a
        home-manager configuration inside a NixOS configuration for
        x86_64-linux is evaluated for x86_64-linux. Any other
        configuration passes on the list it was given.

        Set it on a NixOS configuration that holds a configuration
        for another architecture, such as an image, or on a
        structural or flake level to narrow what is inside it. The
        systems have to be among those allowed where this
        configuration is declared, and one that is not is refused.
      '';
    };

    unsafeCrossChildReferences = lib.mkOption {
      type = lib.types.attrsOf lib.types.bool;
      default = { };
      example = {
        nixos = true;
      };
      description = ''
        By class, whether the configurations of that class declared
        inside this configuration, however many configurations lie
        between, read the full evaluation of this configuration, with
        its children, in place of the childless view of their parent
        (`lib.caisson-core.evalManifest.crossChildLevel`). They can
        then read any configuration declared inside this configuration,
        and a loop between them is a Nix infinite recursion, which the
        childless view otherwise rules out.

        A setting through `caisson.forDirectChildren` beats a setting
        through `caisson.forNearestChildren`, which beats a setting
        here, and within one container the nearest parent that sets it
        wins. A setting here applies to the configurations of the class
        at every level inside this configuration, so
        `caisson.forDirectChildren` or `caisson.forNearestChildren`
        usually fits better.
      '';
    };

  };
}
