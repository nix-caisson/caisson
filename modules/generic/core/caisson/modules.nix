# SPDX-License-Identifier: MIT
{ config, lib, ... }:
let
  registeredModules = config.caisson.manifest.modules;

  # The project each registered module came from, per class and name:
  # null for a module this composition registers itself.
  moduleProjects = config.caisson.manifest.moduleProjects or { };

  # The modules of a class this composition registers itself: a module
  # a consumed project contributed (`<project>/<name>`) leaves only when
  # a selector names it.
  localModules = class: lib.filterAttrs (name: _: (moduleProjects.${class}.${name} or null) == null);

  classConfigFor =
    class:
    config.caisson.modules.${class} or {
      export.enabled = true;
      exported = localModules class;
    };

  exportedClassModules = builtins.mapAttrs (
    class: classModules:
    let
      classConfig = classConfigFor class;
    in
    if classConfig.export.enabled then classConfig.exported classModules else { }
  ) registeredModules;
in
{
  options.caisson.modules = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options = {
            export.enabled = lib.mkEnableOption "module class export";
            exported = lib.mkOption {
              type = lib.types.functionTo (lib.types.attrsOf lib.types.deferredModule);
              default = localModules name;
              defaultText = lib.literalMD "the modules of the class this composition registers itself";
              description = ''
                Function that selects which registered modules to export for this
                class. Receives the modules registered via `mkLib.modules.<class>`
                and returns the subset to publish. Defaults to the modules this
                composition registers itself; a module a consumed project
                contributed (`<project>/<name>`) leaves only when a selector
                names it.
              '';
            };
          };

          config.export.enabled = lib.mkDefault true;
        }
      )
    );
    default = { };
    description = ''
      Export settings for each registered module class.
    '';
  };

  config.caisson.exports.modules = exportedClassModules;
}
