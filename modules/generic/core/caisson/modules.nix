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

  # The classes of the composition: the classes the integrations
  # declare, and the classes that have a registered module. Both are
  # in the library, so they are known before this evaluation starts.
  # The export settings of each class are declared as options from
  # this list. A setting for a class that is not in the list is
  # refused as an option that does not exist.
  classes = lib.lists.unique (
    builtins.attrNames (lib.caisson-core.classes or { })
    ++ builtins.attrNames (lib.caisson-core.libManifest.modules or { })
  );

  exportedClassModules = builtins.mapAttrs (
    class: classModules:
    let
      classConfig = config.caisson.modules.${class};
    in
    if classConfig.export.enabled then classConfig.exported classModules else { }
  ) registeredModules;
in
{
  options.caisson.modules = lib.genAttrs classes (class: {
    export.enabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to export the modules of the class `${class}`.";
    };
    exported = lib.mkOption {
      type = lib.types.functionTo (lib.types.attrsOf lib.types.deferredModule);
      default = localModules class;
      defaultText = lib.literalMD "the modules of the class this composition registers itself";
      description = ''
        Function that selects which registered modules of the class
        `${class}` to export. Receives the modules registered for the
        class and returns the modules to export. Defaults to the
        modules this composition registers itself. A module that came
        from an entry of `projects`, registered as `<project>/<name>`,
        is exported only when the function names it.
      '';
    };
  });

  config.caisson.exports.modules = exportedClassModules;
}
