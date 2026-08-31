# SPDX-License-Identifier: MIT
#
# mkMemoizedDerivationRead: escape import-from-derivation (IFD) by
# *memoizing* the read.
#
# IFD's sin is not that it builds; it is that it makes *evaluation* build,
# smearing a build cost into the pure/cheap phase. `nix flake check
# --no-build` runs eval with a read-only store, so any eval-time
# `readFile "${someDrv}/…"` fails outright ("path … is not valid" / "cannot
# build … during evaluation"). Checks, by contrast, are *supposed* to build.
#
# So we split the IFD in two:
#
#   * `value`: the cached result of the read, taken from a committed file
#     in the source tree. `readFile` of a source path is pure and needs no
#     store build, so evaluation stays cheap and `--no-build` succeeds.
#   * `check`: a derivation that rebuilds `drv`, reads `${drv}/${subpath}`
#     *at build time* (which is not IFD; a derivation reading its own build
#     inputs is ordinary), canonicalizes it, and diffs it against the
#     committed memo. If the derivation's output has drifted from the memo,
#     the check fails loud. This is the memo's cache-invalidation: a memo
#     without a check is a lie you have written down.
#
# The memo and the check are therefore two halves of one thing, which is why
# this helper hands back both and will not let you take one without the
# other.
#
# Equivalence is compared under a `canonicalize` filter, not as raw bytes:
# build outputs legitimately carry ordering / timestamp / host-detected
# noise that does not change meaning. `canonicalize` is an explicit argument.
# The committed memo is stored *already canonical*, so at check time we only
# have to canonicalize the freshly built side and byte-compare.
#
# The eval-time `value` is produced by `normalize` (an arbitrary Nix
# function, e.g. a kconfig parser) applied to the memo. `normalize` and
# `canonicalize` describe the same equivalence at two phases (`normalize`
# in Nix for eval, `canonicalize` in shell for the build-time check) so a
# canonical memo makes them agree by construction.
#
# This is the small general kernel of what haskell.nix "materialization"
# does: commit the generated artifact, ship a check that it is still current,
# and thereby keep it out of evaluation.

# Imported by the core lib overlay as `{ lib = final; }`, exposing
# `lib.caisson.mkMemoizedDerivationRead` for every consumer (mirrors how
# `eval-weight` is wired). Lives in core, not the `default` overlay, because
# `mkLib` only re-applies its own injection downstream; a helper in `default`
# would be invisible to consumers that don't import caisson's own overlay.
{ lib }:

# { pkgs, drv, subpath, memo, normalize ? id, canonicalize ? null }
#   -> { value, check }
#
#   pkgs         package set used to build the check derivation.
#   drv          the derivation whose output we are memoizing a read of.
#   subpath      path under $out to read (e.g. ".config").
#   memo         source-tree path holding the canonical, committed copy
#                of that read. `value = normalize (readFile memo)`.
#   normalize    Nix function applied to the memo's contents to produce
#                `value`. Defaults to identity (raw string).
#   canonicalize optional shell snippet: reads the file named "$1" and
#                writes its canonical form to stdout. Applied to the
#                freshly built `${drv}/${subpath}` before diffing against
#                the (already-canonical) memo. Omit for a raw byte
#                compare. The same filter should have been used to
#                produce the committed memo (see the regenerate helper).
{
  pkgs,
  drv,
  subpath,
  memo,
  normalize ? (x: x),
  canonicalize ? null,
}:
let
  # `canonicalize` is a filter over "$1" -> stdout. Default is identity.
  canonFilter = if canonicalize == null then ''cat "$1"'' else canonicalize;
in
{
  # Pure: readFile of a source path, no store build. Safe under
  # `nix flake check --no-build`.
  value = normalize (builtins.readFile memo);

  # Cache-invalidation. Builds `drv`, canonicalizes its `${subpath}`,
  # and diffs against the committed memo. Fails loud on drift with a
  # diff and the regenerate hint.
  check =
    pkgs.runCommand "memoized-read-check-${baseNameOf (toString memo)}"
      {
        inherit drv;
        memo = memo;
      }
      ''
        set -euo pipefail

        built="$drv/${subpath}"
        if [ ! -e "$built" ]; then
          echo "mkMemoizedDerivationRead: '$built' does not exist in the built output." >&2
          exit 1
        fi

        canonicalized="$(mktemp)"
        ( set -- "$built"; ${canonFilter} ) > "$canonicalized"

        if ! diff -u "$memo" "$canonicalized"; then
          echo >&2
          echo "mkMemoizedDerivationRead: the committed memo has drifted from" >&2
          echo "  ${subpath} produced by $drv." >&2
          echo "  Memo: ${toString memo}" >&2
          echo "  Regenerate it (see the memo's regenerate command) and commit." >&2
          exit 1
        fi

        touch "$out"
      '';
}
