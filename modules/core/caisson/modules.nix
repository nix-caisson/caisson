# SPDX-License-Identifier: MIT
{ config, lib, ... }:
let
  registeredModules = config.caisson.manifest.modules;

  classConfigFor =
    class:
    config.caisson.modules.${class} or {
      export.enabled = true;
      exported = modulesForClass: { };
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
        { ... }:
        {
          options = {
            export.enabled = lib.mkEnableOption "module class export";
            exported = lib.mkOption {
              type = lib.types.functionTo (lib.types.attrsOf lib.types.deferredModule);
              default = modulesForClass: { };
              description = ''
                Function that selects which registered modules to export for this
                class. Receives the modules registered via `mkLib.modules.<class>`
                and returns the subset to publish.
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
