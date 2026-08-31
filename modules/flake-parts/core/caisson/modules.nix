# SPDX-License-Identifier: MIT
{ config, lib, ... }:
let
  registeredModules = config.caisson.manifest.modules // {
    flake = config.caisson.manifest.modules.flake or { };
  };

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
      selectedModules = if classConfig.export.enabled then classConfig.exported classModules else { };
    in
    if class == "flake" then { default = { }; } // selectedModules else selectedModules
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
                and returns the subset to publish under `flake.modules.<class>`.
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

  config = {
    flake.modules = exportedClassModules;
    flake.flakeModules = config.flake.modules.flake;
  };
}
