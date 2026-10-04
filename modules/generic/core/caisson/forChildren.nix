# SPDX-License-Identifier: MIT
#
# What this configuration registers for the configurations beneath it:
# modules, into the registries those configurations select from, and
# additions to the default selection of a class. Both reach every
# configuration beneath this one, at any depth, and nothing at this
# configuration. They are read from the childless view, which the
# configurations beneath are built against.
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

  };
}
