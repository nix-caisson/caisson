#!/usr/bin/env bash
# The errors of deferred configurations and the NixOps4 integrations,
# read as text. A tool reads the error of a deferred configuration to
# tell an arg it lacks (`caisson-deferred: needs <path>`) from a
# failure, and the integrations refuse what they cannot evaluate with
# errors that name the configuration. `builtins.tryEval` hides the
# text of an error, so this runs the real evaluator on each case of
# cases.nix and looks for the line the case names in what it prints.
#
#   check.sh LIB_EXPR NIXOPS4_SRC [nix eval flag...]
#
# LIB_EXPR is a Nix expression for the composed library and NIXOPS4_SRC
# the path of the NixOps4 source; the flags follow `nix eval`. The
# flake check composes the library from store paths, as the check of
# tests/argument-errors does.
set -euo pipefail

lib_expr="$1"
nixops4="$2"
shift 2
flags=("$@")

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cases="(import $here/cases.nix { lib = $lib_expr; nixops4 = \"$nixops4\"; })"

names="$(nix eval "${flags[@]}" --raw --expr "builtins.concatStringsSep \"\n\" (builtins.attrNames $cases)")"

failures=0
while IFS= read -r name; do
  message="$(nix eval "${flags[@]}" --raw --expr "$cases.$name.message")"
  # `nix eval` prints an error inside a value in place of failing, so
  # the value is forced whole first.
  if out="$(nix eval "${flags[@]}" --expr "let value = $cases.$name.value; in builtins.deepSeq value true" 2>&1)"; then
    printf 'FAIL %s: evaluated without an error:\n%s\n\n' "$name" "$out"
    failures=$((failures + 1))
  elif grep -qF -- "$message" <<< "$out"; then
    printf 'ok   %s\n' "$name"
  else
    printf 'FAIL %s: the error does not contain\n  %s\n%s\n\n' "$name" "$message" "$out"
    failures=$((failures + 1))
  fi
done <<< "$names"

if [ "$failures" -ne 0 ]; then
  printf '%d case(s) failed\n' "$failures"
  exit 1
fi
