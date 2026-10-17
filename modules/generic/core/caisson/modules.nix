# SPDX-License-Identifier: MIT
{
  config,
  lib,
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
  # this evaluation starts. A setting for a class that is not in the
  # list is refused.
  evalManifest = lib.caisson-core.evalManifest;
  classes = lib.lists.unique (
    builtins.attrNames lib.caisson.modules
    ++ builtins.attrNames (if evalManifest == null then { } else evalManifest.modules or { })
  );

  settings = config.caisson.modules;
  unknown = builtins.filter (class: !(builtins.elem class classes)) (builtins.attrNames settings);
  settingsNames = [
    "export"
    "exported"
  ];

  # The settings of a class: `export.enabled`, true unless set, and
  # `exported`, the function that selects the modules to export, the
  # modules the composition registers itself unless set.
  settingsOf =
    class:
    let
      set = settings.${class} or { };
      others = builtins.filter (name: !(builtins.elem name settingsNames)) (builtins.attrNames set);
      enabled = (set.export or { }).enabled or true;
    in
    if others != [ ] then
      throw "`caisson.modules.${class}` sets ${lib.concatStringsSep ", " others}; the settings of a class are `export.enabled` and `exported`."
    else if !builtins.isBool enabled then
      throw "`caisson.modules.${class}.export.enabled` must be a boolean."
    else
      {
        inherit enabled;
        exported = set.exported or (localModules class);
      };

  exportedClassModules =
    if unknown != [ ] then
      throw ''
        `caisson.modules` sets the export of ${lib.concatMapStringsSep ", " (class: "`${class}`") unknown},
        which no module is registered for. The classes are: ${lib.concatStringsSep ", " classes}.
      ''
    else
      builtins.mapAttrs (
        class: classModules:
        let
          classSettings = settingsOf class;
        in
        if classSettings.enabled then classSettings.exported classModules else { }
      ) registeredModules;
in
{
  # The export settings of each class, in one option for every class:
  # a class no module sets costs nothing to evaluate, where options per
  # class would be merged in every evaluation for every class, and a
  # submodule per class would be an evaluation of its own.
  options.caisson.modules = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.lazyAttrsOf lib.types.raw);
    default = { };
    description = ''
      The export settings of the registered modules, by class.
      `caisson.modules.<class>.exported` is the function that selects
      which registered modules of the class to export: it receives the
      modules registered for the class and returns the modules to
      export. It defaults to the modules this composition registers
      itself; a module that came from an entry of `projects`,
      registered as `<project>/<name>`, is exported only when the
      function names it. `caisson.modules.<class>.export.enabled`,
      true unless set, turns the export of the class off. A class with
      a registered module can be set; any other class is refused.
    '';
  };

  config.caisson.exports.modules = exportedClassModules;
}
