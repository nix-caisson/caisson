# SPDX-License-Identifier: MIT
#
# The nixpkgs-lib integration: it brings the library of nixpkgs
# (`lib.mkOption`, `lib.evalModules`, `lib.types` and the rest) into a
# composed library. caisson-core composes a library out of entries and
# knows no ecosystem; this file is where a caisson composition learns
# which sources carry nixpkgs' library and where it sits in them.
#
# What it does: it finds the source that supplies the library and
# merges that source's `lib` into the composed library, as the source
# fixes it.
#
# The source is the one the composition supplies for the ecosystem
# `nixpkgs-lib` (the library part declared separately: the nixpkgs.lib
# mirror, or nixpkgs' `lib` directory), else the one it supplies for
# the ecosystem `nixpkgs` (a nixpkgs checkout, one pin supplying every
# part). What a composition supplies for an ecosystem is its
# `defaultEcosystemSrc.<name>`, else the source it pins under that
# exact name.
#
# The source is read from `prev.caisson-core.ecosystemSrc`, which
# caisson-core publishes in the first layers of a library from the
# arguments of the mkLib call. So this entry loads the nixpkgs library
# of the composition it is composed into: composed in a tree that
# takes caisson as a project, it reads the source that tree declares,
# and the pin of caisson plays no part. It has to be `prev`: the names
# this entry adds come from the source, so the source cannot be read
# out of the fixpoint those names are part of.
#
# With no source the entry fails where it is composed, naming the
# declaration.
#
# nixpkgs' lib/default.nix builds its fixpoint with a bootstrap
# makeExtensible that exposes `extend` only, no `__unfix__`, so the
# library cannot be re-tied over the composed fixpoint here. An
# overlay composed later overrides a name for readers of the composed
# library, and not for upstream's internal references.
#
# An overlay that calls nixpkgs' functions through the composed
# library imports this entry by the key `nixpkgs-lib`, so composing
# that overlay composes this. A tree outside caisson imports it from
# the caisson source tree, as it imports `integrations`:
#
#   (mkLibOverlay (closure-inputs.caisson.outPath + "/lib-overlays/nixpkgs-lib"))
#   // { key = "nixpkgs-lib"; }
{ ... }:
{
  imports = [ ];
  overlay =
    _final: prev:
    let
      # Null for every name in a library that caisson-core's entries
      # are not part of.
      supplied = (prev.caisson-core or { }).ecosystemSrc or (_name: null);
      src = if supplied "nixpkgs-lib" != null then supplied "nixpkgs-lib" else supplied "nixpkgs";
      root =
        if src == null then
          builtins.throw ''
            caisson: the `nixpkgs-lib` entry has no source. Declare
            `defaultEcosystemSrc.nixpkgs-lib` (the nixpkgs.lib mirror, or nixpkgs'
            `lib` directory) or `defaultEcosystemSrc.nixpkgs` (a nixpkgs checkout)
            in the mkLib call, or pin a source named exactly `nixpkgs-lib` or
            `nixpkgs` in the `sources` passed to mkLib.
          ''
        else
          "${src}";
      # A tree holding the `lib` directory, or that directory.
      libDir = if builtins.pathExists "${root}/lib/default.nix" then "${root}/lib" else root;
    in
    prev // builtins.import libDir;
}
