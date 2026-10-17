# SPDX-License-Identifier: MIT
{
  config,
  lib,
  options,
  ...
}:
let
  registeredModules = config.caisson.manifest.modules;

  # The project each registered module came from, per class and name:
  # null for a module this composition registers itself.
  moduleProjects = config.caisson.manifest.moduleProjects or { };

  # The modules of a class this composition registers itself: a module
  # a consumed project contributed (`<project>/<name>`) leaves only when
  # a selector names it.
  localModules = class: lib.filterAttrs (name: _: (moduleProjects.${class}.${name} or null) == null);

  # The classes that have a registered module, in the registry of the
  # library and in the registry the manifest of this evaluation holds.
  # Both manifests are in the library, so the classes are known before
  # this evaluation starts. The export settings of each class are
  # declared as options from this list. A setting for a class that is
  # not in the list is refused as an option that does not exist.
  evalManifest = lib.caisson-core.evalManifest;
  classes = lib.lists.unique (
    builtins.attrNames lib.caisson.modules
    ++ builtins.attrNames (if evalManifest == null then { } else evalManifest.modules or { })
  );

  # The types of the options, built once for every class. The modules
  # are exported as they were registered.
  types = {
    enabled = lib.types.bool;
    exported = lib.types.functionTo (lib.types.lazyAttrsOf lib.types.raw);
  };

  # True when a module of the evaluation defines the option: its highest
  # priority is above the priority of an option default.
  defined = option: option.highestPrio < 1500;

  # A class whose options no module defines exports its default, the
  # modules the composition registers itself, without merging the two
  # options, which spares merging them in every evaluation for every
  # class.
  exportedClassModules = builtins.mapAttrs (
    class: classModules:
    let
      classOptions = options.caisson.modules.${class};
      classConfig = config.caisson.modules.${class};
    in
    if !(defined classOptions.export.enabled) && !(defined classOptions.exported) then
      localModules class classModules
    else if classConfig.export.enabled then
      classConfig.exported classModules
    else
      { }
  ) registeredModules;
in
{
  options.caisson.modules = lib.genAttrs classes (class: {
    export.enabled = lib.mkOption {
      type = types.enabled;
      default = true;
      description = "Whether to export the modules of the class `${class}`.";
    };
    exported = lib.mkOption {
      type = types.exported;
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
