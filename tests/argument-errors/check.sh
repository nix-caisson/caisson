#!/usr/bin/env bash
# The argument error of every entry point comes from Nix itself, raised
# at the call site: between `error:` and the message stands the call site and
# nothing of caisson. nix-unit matches messages and cannot see frames,
# so this runs the real evaluator against each entry point with a
# wrong call and reads the trace.
#
#   check.sh LIB_EXPR [nix eval flag...]
#
# LIB_EXPR is a Nix expression for the composed library; the flags
# follow `nix eval`. From a checkout, against the flake's library:
#
#   tests/argument-errors/check.sh \
#     'let f = builtins.getFlake "path:'"$PWD"'"; in f.lib' --impure
#
# The flake check composes the library from store paths instead.
set -euo pipefail

lib_expr="$1"
shift
flags=("$@")

# Every entry point takes `configModule` and `pkgSets`; the `nixos`
# ones require `pkgSets` too, so an empty call may report either.
namespaces=(
  nixos
  nixos-minimal
  home-manager
  home-manager-minimal
  flake-parts
  structural
  colmena
  terranix
  system-manager
)

failures=0

# The trace of a failing evaluation, with the warnings a dirty tree
# prints dropped.
trace_of() {
  local expr="let lib = $lib_expr; in $1"
  local out
  if out="$(nix eval "${flags[@]}" --expr "$expr" 2>&1)"; then
    printf 'evaluated without an error:\n%s\n' "$out"
    return 1
  fi
  grep -v '^warning: ' <<< "$out" || true
}

# The location line under each `…` frame of a trace.
frame_locations() {
  awk '/^[[:space:]]*… /{f=1;next} f&&/^[[:space:]]*at /{print;f=0}' <<< "$1"
}

# check LABEL CALL MESSAGE_REGEX: the trace of CALL carries a message
# matching MESSAGE_REGEX and exactly one frame, the call site in this
# expression.
check() {
  local label="$1" call="$2" want="$3"
  local trace frames
  if ! trace="$(trace_of "$call")"; then
    printf 'FAIL %s\n%s\n\n' "$label" "$trace"
    failures=$((failures + 1))
    return
  fi
  frames="$(grep -c '^[[:space:]]*… ' <<< "$trace" || true)"
  if ! grep -Eq "error: $want" <<< "$trace"; then
    printf 'FAIL %s: the message is not the native argument error\n%s\n\n' "$label" "$trace"
    failures=$((failures + 1))
  elif [ "$frames" != 1 ] || ! grep -q '^[[:space:]]*… from call site' <<< "$trace" \
    || ! frame_locations "$trace" | grep -q '«string»'; then
    printf 'FAIL %s: %s frame(s), expected the call site alone\n%s\n\n' "$label" "$frames" "$trace"
    failures=$((failures + 1))
  else
    printf 'ok   %s\n' "$label"
  fi
}

# check_node LABEL CALL MESSAGE_REGEX: the trace of CALL, which
# reaches a node constructor through a module evaluation, carries a
# message matching MESSAGE_REGEX, and the last frame above the message
# is the one where the module system evaluates the definitions the
# constructor was called from: a frame of the constructor itself would
# stand between that frame and the message.
check_node() {
  local label="$1" call="$2" want="$3"
  local trace below
  if ! trace="$(trace_of "$call")"; then
    printf 'FAIL %s\n%s\n\n' "$label" "$trace"
    failures=$((failures + 1))
    return
  fi
  below="$(sed -n '/^[[:space:]]*… while evaluating definitions from/,$p' <<< "$trace" | tail -n +2)"
  if ! grep -Eq "error: $want" <<< "$trace"; then
    printf 'FAIL %s: the message is not the native argument error\n%s\n\n' "$label" "$trace"
    failures=$((failures + 1))
  elif [ -z "$below" ] || grep -q '^[[:space:]]*… ' <<< "$below"; then
    printf 'FAIL %s: a frame stands between the module system and the message\n%s\n\n' "$label" "$trace"
    failures=$((failures + 1))
  else
    printf 'ok   %s\n' "$label"
  fi
}

missing="function '[^']*%s' called without required argument '(configModule|pkgSets)'"
unexpected="function '[^']*%s' called with unexpected argument 'bogus'"

for ns in "${namespaces[@]}"; do
  for fn in mkConfiguration mkConfigurationWithEcosystemArgs; do
    ep="lib.caisson.$ns.$fn"
    # shellcheck disable=SC2059
    check "$ns.$fn { }" "$ep { }" "$(printf "$missing" "$fn")"
    # shellcheck disable=SC2059
    check "$ns.$fn { bogus, configModule, pkgSets.pkgs }" \
      "$ep { bogus = 1; configModule = { }; pkgSets.pkgs = { }; }" "$(printf "$unexpected" "$fn")"
  done
  # The twin admits `ecosystemArgs`; the entry point refuses it.
  # shellcheck disable=SC2059
  check "$ns.mkConfigurationWithEcosystemArgs { bogus, ecosystemArgs, ... }" \
    "lib.caisson.$ns.mkConfigurationWithEcosystemArgs { bogus = 1; configModule = { }; pkgSets.pkgs = { }; ecosystemArgs = { }; }" \
    "$(printf "$unexpected" mkConfigurationWithEcosystemArgs)"
  check "$ns.mkConfiguration { ecosystemArgs, ... }" \
    "lib.caisson.$ns.mkConfiguration { configModule = { }; pkgSets.pkgs = { }; ecosystemArgs = { }; }" \
    "function '[^']*mkConfiguration' called with unexpected argument 'ecosystemArgs'"
done

# shellcheck disable=SC2059
check "nixos.mkConfigurationFull { }" "lib.caisson.nixos.mkConfigurationFull { }" "$(printf "$missing" mkConfigurationFull)"
# shellcheck disable=SC2059
check "nixos.mkConfigurationFull { bogus, configModule, pkgSets.pkgs }" \
  "lib.caisson.nixos.mkConfigurationFull { bogus = 1; configModule = { }; pkgSets.pkgs = { }; }" \
  "$(printf "$unexpected" mkConfigurationFull)"

# The colmena node constructors, module arguments of a colmena
# configuration, reached through a stand-in colmena source with the
# two attributes the integration reads.
colmena_stub='{ lib.makeHive = _: { __schema = "v0.5"; }; nixosModules = { deploymentOptions = { }; assertionModule = { }; keyChownModule = { }; keyServiceModule = { }; }; }'
node_call() {
  printf '(lib.caisson.colmena.mkConfiguration { ecosystemSrc = %s; configModule = { %s, ... }: { nodes.probe = %s %s; }; }).nodes.probe' \
    "$colmena_stub" "$1" "$1" "$2"
}
for fn in mkNixosConfiguration mkNixosConfigurationWithEcosystemArgs; do
  # shellcheck disable=SC2059
  check_node "colmena node $fn { }" "$(node_call "$fn" '{ }')" "$(printf "$missing" "$fn")"
  # shellcheck disable=SC2059
  check_node "colmena node $fn { bogus, configModule, pkgSets.pkgs }" \
    "$(node_call "$fn" '{ bogus = 1; configModule = { }; pkgSets.pkgs = { }; }')" "$(printf "$unexpected" "$fn")"
done

if [ "$failures" != 0 ]; then
  printf '%s check(s) failed\n' "$failures"
  exit 1
fi
printf 'every argument error is native and raised at the call site\n'
