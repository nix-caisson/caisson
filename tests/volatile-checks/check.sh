#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Builds the checks of tests/volatile-checks/default.nix into the local
# Nix store and reads the store after each build with `nix path-info`.
# A passing check writes its pass marker, at the output path its
# derivation declares, holding `pass`; building it again with
# `--rebuild` runs the program again and keeps the marker. A failing
# check fails to build, and no marker is valid at its output path.
#
#   tests/volatile-checks/check.sh
#
# The pinned-world suite holds what evaluation shows of the derivation
# (its name, its fixed output and its `drvAttrs`); this script holds
# what only a build shows.

set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
nonce="run-$(date +%s)-$$"
failures=0

fail() {
  echo "check.sh: FAIL: $*" >&2
  failures=$((failures + 1))
}

checks=(--impure --file "$repo/tests/volatile-checks" --argstr nonce "$nonce")

output_of() {
  nix eval --raw "${checks[@]}" "$1.outPath"
}

passing=$(output_of passing)
failing=$(output_of failing)

for marker in "$passing" "$failing"; do
  if nix path-info "$marker" >/dev/null 2>&1; then
    fail "$marker is valid in the local store before any build"
  fi
done

# A pass writes the marker at the declared output path.
built=$(nix build --no-link --print-out-paths "${checks[@]}" passing) || fail "the passing check did not build"
[[ $built == "$passing" ]] || fail "the passing check built $built, not $passing"
nix path-info "$passing" >/dev/null 2>&1 || fail "$passing is not valid in the local store after a pass"
[[ $(cat "$passing") == pass ]] || fail "$passing does not hold pass"

# The program runs again with --rebuild, and the marker stays.
nix build --no-link --rebuild "${checks[@]}" passing || fail "the passing check did not build again with --rebuild"
nix path-info "$passing" >/dev/null 2>&1 || fail "$passing is not valid in the local store after the rebuild"

# A failure leaves no marker.
if nix build --no-link "${checks[@]}" failing; then
  fail "the failing check built"
fi
if nix path-info "$failing" >/dev/null 2>&1; then
  fail "$failing is valid in the local store after a failure"
fi

if ((failures)); then
  echo "check.sh: $failures expectations failed" >&2
  exit 1
fi
echo "check.sh: every expectation holds"
