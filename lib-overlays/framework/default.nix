# SPDX-License-Identifier: MIT
#
# The names of the framework under `lib.caisson`: what a tree built
# with caisson writes to compose its library and register its modules,
# overlays and configurations. A user of caisson names `caisson` and
# nothing else.
#
# caisson-core supplies the machinery. This overlay publishes the part
# of it that a tree writes, under `lib.caisson`, each name being the
# value of the same name under `lib.caisson-core` in the same library.
# The rest of `lib.caisson-core` is what integrations and caisson
# itself are written on.
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

  # The names, read from `lib.caisson-core`. Each is read when it is
  # used, so a library that lacks one (an earlier stage has no
  # configurations yet) fails for that name alone.
  # What caisson holds itself, bound to no library: the readers of pin
  # files, which hand `mkLib` its `sources` and `root`, and the
  # functions that evaluate a flake from source over inputs supplied
  # by hand, which a tree uses to check consumer-style flakes.
  pins = builtins.import ./pins;
  callFlake = builtins.import ./call-flake.nix;
  callConsumerFlake = builtins.import ./call-consumer-flake.nix;

  namesIn = lib: {
    inherit pins callFlake callConsumerFlake;
    inherit (lib.caisson-core)
      # making entries, and reading them from directories
      mkModule
      mkModules
      mkLibOverlay
      mkLibOverlays
      mkPkgOverlay
      mkPkgOverlays
      importApply
      # the registries
      modules
      configs
      classes
      libOverlays
      pkgOverlays
      pkgOverlaysFor
      # the manifests
      libManifest
      pkgsManifest
      evalManifest
      manifestOf
      # what an integration written outside caisson uses
      contributeClasses
      contributeModules
      finalizeTop
      elide
      ecosystemSrc
      ;
    mkLib = mkLibIn lib;
  };

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
