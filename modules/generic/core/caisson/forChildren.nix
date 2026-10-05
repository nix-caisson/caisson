# SPDX-License-Identifier: MIT
#
# What this configuration offers the configurations beneath it, nested
# ones included: modules, which join the registries those
# configurations select from; additions to the default selection of a
# class, which a configuration gets when it passes no `moduleImports`;
# and a default package set, which a configuration runs on when
# neither it nor a configuration between selects another. This
# configuration is not among those they are offered to. They are read
# from the childless view, which the configurations beneath are built
# against.
{ lib, ... }:
{
  options.caisson.forChildren = {

    modules = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.deferredModule);
      default = { };
      example = lib.literalExpression ''
        {
          nixos.gaming = { pkgs, ... }: { programs.steam.enable = true; };
        }
      '';
      description = ''
        Modules registered for the configurations beneath this
        configuration, by class and then name. An entry joins the
        registry of its class as those configurations see it
        (`lib.caisson-core.modules.<class>.<name>`), where a
        configuration selects it with `moduleImports`. An entry under a
        name the registry already holds replaces it beneath this
        configuration. Definitions of the same entry from several
        modules merge.
      '';
    };

    defaultModuleImports = lib.mkOption {
      type = lib.types.attrsOf (lib.types.functionTo (lib.types.listOf lib.types.raw));
      default = { };
      example = lib.literalExpression ''
        {
          nixos = lib: [ lib.caisson-core.modules.nixos.gaming ];
        }
      '';
      description = ''
        Additions to the default selection of a class for the
        configurations beneath this configuration: by class, a
        function of the lib of such a configuration returning
        registered modules. A configuration that passes no
        `moduleImports` gets every entry named `default` followed by
        these, those of the levels above it first. Definitions from
        several modules are concatenated.
      '';
    };

    defaultPkgs = lib.mkOption {
      type = lib.types.nullOr (lib.types.functionTo lib.types.raw);
      default = null;
      example = lib.literalExpression "pkgSets: pkgSets.stable";
      description = ''
        The package set the configurations beneath this configuration
        get by default: a function that receives the package sets
        available to such a configuration, as an attribute set by
        package config name, and returns the set to run on. A
        configuration beneath runs on it unless that configuration, or
        a configuration between the two, is constructed with
        `defaultPkgs` or sets this option. This configuration runs on
        the set it was constructed with. When null, the default
        beneath is the selection in force at this configuration.
      '';
    };

  };
}
