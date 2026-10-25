# SPDX-License-Identifier: MIT
#
# What a flake that uses caisson calls to compose its library and to
# register its modules, overlays and configurations, under
# `lib.caisson`: `mkLib`, `mkModules`, `mkLibOverlays`, the registries,
# the manifests. With these a flake writes `lib.caisson.<name>` for
# everything it calls and does not have to write `caisson-core`.
#
# caisson-core supplies the machinery. This overlay publishes the part
# of it that a flake calls, under `lib.caisson`, each name being the
# value of the same name under `lib.caisson-core` in the same library.
# The registries are the exception: caisson-core keeps them in the
# manifest of the library, and `lib.caisson.modules`,
# `lib.caisson.configs`, `lib.caisson.libOverlays` and
# `lib.caisson.pkgOverlays` read them from there. The rest of
# `lib.caisson-core` is what integrations and caisson itself are
# written on.
#
# `mkLib` is the exception to "the same value": it is the `mkLib` of
# caisson-core with one thing added. Several of its arguments are
# functions of a library that is still being built (`libOverlays`
# receives a library that holds caisson-core alone, before any overlay
# of caisson is composed). `lib.caisson.mkLib` hands each of those
# functions its library with these names under `lib.caisson`, so every
# argument is written the same way:
#
#   lib = caisson.lib.caisson.mkLib {
#     inherit (caisson.lib.caisson.pins.flake inputs) sources root;
#     projects = { inherit caisson; };
#     modules = lib: lib.caisson.mkModules ./modules;
#     libOverlays = lib: lib.caisson.mkLibOverlays ./lib-overlays;
#   };
#
# It imports nothing and uses builtins only.
{ ... }:
let

  # What caisson holds itself, bound to no library: the readers of pin
  # files, which hand `mkLib` its `sources` and `root`, the functions
  # that evaluate a flake from source over inputs supplied by hand,
  # which a flake uses to check consumer-style flakes, and the
  # function that realizes resolved inputs, for a tool that
  # evaluates a flake inside a build sandbox.
  pins = builtins.import ./pins;
  callFlake = builtins.import ./call-flake.nix;
  callConsumerFlake = builtins.import ./call-consumer-flake.nix;
  realizeInputs = builtins.import ./realize-inputs.nix;

  # The names under `lib.caisson`: those above, and the rest read
  # from `lib.caisson-core`. Each is read when it is used, so a library
  # that lacks one fails for that name alone.
  namesIn = lib: {
    inherit
      pins
      callFlake
      callConsumerFlake
      realizeInputs
      ;
    inherit (lib.caisson-core)
      # making entries, and reading them from directories
      mkModule
      mkModules
      mkLibOverlay
      mkLibOverlays
      mkPkgOverlay
      mkPkgOverlays
      importApply
      pkgOverlaysFor
      # the manifests
      libManifest
      pkgsManifest
      evalManifest
      manifestOf
      # what an integration written outside caisson uses
      finalizeTop
      elide
      ecosystemSrc
      ;
    mkLib = mkLibIn lib;
    # the registries
    modules = keyedModules lib (registryIn lib "modules");
    configs = keyedConfigs lib (registryIn lib "configs");
    libOverlays = registryIn lib "libOverlays";
    pkgOverlays = registryIn lib "pkgOverlays";
  };

  # The module registry as a selection reads it: each module wrapped
  # in two modules, one inside the other, the inner one importing the
  # module.
  #
  # The outer module is keyed `modules.<class>.<name>@<project>`: the
  # name of the entry in the registry being read and the project that
  # registered it. A registry names an entry of a listed project
  # `<project>/<name>`, and the registry of that project names the
  # same entry `<name>`. The outer key tells which registry entry a
  # module of the evaluation is, as the registry it was read from
  # names it, for the `declaration` events of the evaluation and its
  # selection record (`lib.caisson.integrations.declarationEventsOf`,
  # `lib.caisson.integrations.selectionAccountOf`).
  #
  # The inner module is keyed `registered.modules.<class>.<name>@<project>`,
  # with the name the entry has in the registry of the project that
  # registered it. That name is the registry name with the leading
  # `<project>/` removed, when the manifest records the entry as
  # contributed by `<project>` (`moduleProjects`). An entry the tree
  # registers itself keeps its registry name, whatever it holds, and
  # its project is the name of the tree. So the inner key is the same
  # whichever registry an evaluation reads the entry from. The entries
  # of caisson are an example: caisson registers `default`, a tree that
  # lists caisson reads it as `caisson/default`, and an integration
  # reads it as `default` from the library of caisson.
  #
  # The module system imports the modules that share a key once. An
  # entry that an evaluation selects twice, from one registry or from
  # two, is therefore imported once. Entries of the same name that
  # different projects register stay apart, since their projects
  # differ.
  keyedModules =
    lib:
    let
      manifest = lib.caisson-core.libManifest or { };
      local = manifest.name or null;
      registeredBy = class: name: (manifest.moduleProjects or { }).${class}.${name} or null;
      projectOf =
        class: name:
        let
          registered = registeredBy class name;
        in
        if registered != null then
          registered
        else if local != null then
          local
        else
          "";
      nameInProjectOf =
        class: name:
        let
          registered = registeredBy class name;
          prefix = "${registered}/";
          length = builtins.stringLength prefix;
        in
        if registered != null && builtins.substring 0 length name == prefix then
          builtins.substring length (builtins.stringLength name - length) name
        else
          name;
    in
    builtins.mapAttrs (
      class:
      builtins.mapAttrs (
        name: module:
        let
          project = projectOf class name;
        in
        {
          key = "modules.${class}.${name}@${project}";
          imports = [
            {
              key = "registered.modules.${class}.${nameInProjectOf class name}@${project}";
              imports = [ module ];
            }
          ];
        }
      )
    );

  # The configuration registry as an integration reads it: each
  # configuration module wrapped in a module that imports it, keyed
  # `configs.<class>.<name>@<project>`. The configurations of a registry
  # are those of the tree that registered them: mkLib takes no
  # configuration from a listed project, so a registry name is the name
  # in the registering tree, and the project is the name of the tree.
  # The key is therefore the same in every library that holds the
  # entry, and one module keys it. The key names the registry entry in the
  # `declaration` events of an evaluation, whether the configuration
  # was taken by its name or a configuration was given the entry as its
  # `configModule`.
  keyedConfigs =
    lib:
    let
      project = (lib.caisson-core.libManifest or { }).name or "";
    in
    builtins.mapAttrs (
      class:
      builtins.mapAttrs (
        name: module: {
          key = "configs.${class}.${name}@${project}";
          imports = [ module ];
        }
      )
    );

  # A registry, read from the manifest of the library. A registry is
  # empty in a library that no mkLib built, and in a stage of the
  # library that does not hold it yet: the registered modules,
  # configurations and package overlays join the manifest after the
  # stage that the `modules` function receives.
  registryIn =
    lib: name:
    let
      manifest = lib.caisson-core.libManifest or null;
    in
    if manifest == null then { } else manifest.${name} or { };

  # The library a function argument of mkLib receives, with the names
  # under `caisson` beside whatever the stage already holds there.
  present = lib: lib // { caisson = namesIn lib // (lib.caisson or { }); };

  # The arguments of mkLib that are functions of a library being
  # built. One left out, null, or not a function is passed as given,
  # so the defaults and the errors of caisson-core stay as they are.
  libraryArguments = [
    "modules"
    "configs"
    "libOverlays"
    "libOverlayImports"
    "extraLibOverlayImports"
    "pkgOverlays"
    "pkgSets"
  ];

  mkLibIn =
    lib: args:
    lib.caisson-core.mkLib (
      if !builtins.isAttrs args then
        args
      else
        args
        // builtins.listToAttrs (
          builtins.concatMap (
            name:
            if builtins.isFunction (args.${name} or null) then
              [
                {
                  inherit name;
                  value = given: args.${name} (present given);
                }
              ]
            else
              [ ]
          ) libraryArguments
        )
    );

in
{
  imports = [ ];
  overlay = final: prev: {
    caisson = (prev.caisson or { }) // namesIn final;
  };
}
