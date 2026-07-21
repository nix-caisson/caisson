# SPDX-License-Identifier: MIT
# Measures where Nix evaluation weight goes for a flake's configurations.
# Each target is evaluated in cumulative stages by separate evaluator
# processes; the per-stage deltas attribute weight to flake machinery,
# module-system fixpoint, package-set forcing, and full instantiation.

usage() {
  cat <<'EOF'
eval-weight-report — measure Nix evaluation weight of flake configurations

Usage: eval-weight-report [options] [TARGET...]

TARGETs are attribute names under nixosConfigurations or
homeConfigurations (bare names are measured under both if present), or
full paths like nixosConfigurations.myhost. With no TARGETs, everything
under nixosConfigurations and homeConfigurations is measured.

Options:
  --flake REF    flake to measure (default: .)
  --out DIR      write raw per-stage stats JSON (and flamegraphs) to DIR
  --flamegraph   also capture an evaluator flamegraph per target into the
                 --out dir (folded stacks; render with flamegraph.pl or
                 inferno-flamegraph)
  -h, --help     show this help

Stages (cumulative, so each Δ row isolates one layer):
  shallow    flake output machinery up to selecting the configuration
  config     module-system fixpoint far enough to read one merged option
  packages   forcing the configuration's package list
  toplevel   full instantiation of the build product (drvPath)

The thunks/values/envs/calls/alloc columns are deterministic for a fixed
lock set and Nix version and are comparable across machines, as are the
semantic counters: npkgs (full nixpkgs instantiations), libs (nixpkgs-lib
bootstraps), and modsys (evalModules calls, incl. submodules). The cpu
and wall columns are machine- and load-dependent, informational only.
EOF
}

flake="."
outDir=""
flamegraph=0
declare -a rawTargets=()

while [ $# -gt 0 ]; do
  case "$1" in
    --flake)
      flake="$2"
      shift 2
      ;;
    --out)
      outDir="$2"
      shift 2
      ;;
    --flamegraph)
      flamegraph=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      rawTargets+=("$1")
      shift
      ;;
  esac
done

if [ "$flamegraph" -eq 1 ] && [ -z "$outDir" ]; then
  outDir=$(mktemp -d -t eval-weight-report.XXXXXX)
  echo "note: --flamegraph without --out; writing to $outDir" >&2
fi
[ -z "$outDir" ] || mkdir -p "$outDir"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

nixEval() {
  nix eval --option eval-cache false "$@"
}

listNames() {
  # $1: output attr (nixosConfigurations / homeConfigurations)
  nixEval "$flake#$1" --apply builtins.attrNames --json 2>/dev/null || echo '[]'
}

# Resolve targets into "kind<TAB>name" lines.
resolveTargets() {
  local nixosNames homeNames
  nixosNames=$(listNames nixosConfigurations)
  homeNames=$(listNames homeConfigurations)
  if [ "${#rawTargets[@]}" -eq 0 ]; then
    jq -r '.[] | "nixos\t\(.)"' <<< "$nixosNames"
    jq -r '.[] | "home\t\(.)"' <<< "$homeNames"
    return
  fi
  local t
  for t in "${rawTargets[@]}"; do
    case "$t" in
      nixosConfigurations.*)
        printf 'nixos\t%s\n' "${t#nixosConfigurations.}"
        ;;
      homeConfigurations.*)
        printf 'home\t%s\n' "${t#homeConfigurations.}"
        ;;
      *)
        local found=0
        if jq -e --arg n "$t" 'index($n) != null' <<< "$nixosNames" > /dev/null; then
          printf 'nixos\t%s\n' "$t"
          found=1
        fi
        if jq -e --arg n "$t" 'index($n) != null' <<< "$homeNames" > /dev/null; then
          printf 'home\t%s\n' "$t"
          found=1
        fi
        if [ "$found" -eq 0 ]; then
          echo "warning: target '$t' not found in nixosConfigurations or homeConfigurations" >&2
        fi
        ;;
    esac
  done
}

stageExpr() {
  # $1: kind, $2: stage
  case "$1.$2" in
    nixos.shallow | home.shallow) echo 'c: "forced"' ;;
    nixos.config) echo 'c: c.config.system.stateVersion' ;;
    nixos.packages) echo 'c: builtins.length c.config.environment.systemPackages' ;;
    nixos.toplevel) echo 'c: c.config.system.build.toplevel.drvPath' ;;
    home.config) echo 'c: c.config.home.stateVersion' ;;
    home.packages) echo 'c: builtins.length c.config.home.packages' ;;
    home.toplevel) echo 'c: c.activationPackage.drvPath' ;;
  esac
}

attrPath() {
  # $1: kind, $2: name — leaf always quoted (names may contain @)
  case "$1" in
    nixos) printf 'nixosConfigurations."%s"' "$2" ;;
    home) printf 'homeConfigurations."%s"' "$2" ;;
  esac
}

# npkgs/libs/modsys count full nixpkgs instantiations, nixpkgs-lib
# bootstraps, and evalModules calls (incl. submodules), derived from
# NIX_COUNT_CALLS positions anchored to stable names, not line numbers.
extract='{
  thunks: .nrThunks,
  values: .values.number,
  envs: .envs.number,
  calls: (.nrFunctionCalls + .nrPrimOpCalls),
  allocMB: ((.gc.totalBytes / 1048576 * 10 | round) / 10),
  npkgs: ([(.functions // [])[]
    | select((.file // "" | endswith("pkgs/top-level/default.nix"))
             and .column == 1 and .name == null)
    | .count] | add // 0),
  libs: ([(.functions // [])[]
    | select((.file // "" | endswith("/lib/default.nix"))
             and (.name // "" | startswith("makeExtensible")))
    | .count] | add // 0),
  modsys: ([(.functions // [])[]
    | select((.file // "" | endswith("/lib/modules.nix"))
             and .name == "evalModules")
    | .count] | add // 0),
  cpu: ((.cpuTime * 100 | round) / 100)
}'

header() {
  printf '%-14s %12s %12s %12s %12s %9s %6s %5s %7s %7s %7s\n' \
    "stage" "thunks" "values" "envs" "calls" "allocMB" "npkgs" "libs" "modsys" "cpu*" "wall*"
}

row() {
  # $1 stage label, $2 metrics json, $3 wall seconds
  printf '%-14s %12s %12s %12s %12s %9s %6s %5s %7s %7s %7s\n' \
    "$1" \
    "$(jq -r '.thunks' <<< "$2")" \
    "$(jq -r '.values' <<< "$2")" \
    "$(jq -r '.envs' <<< "$2")" \
    "$(jq -r '.calls' <<< "$2")" \
    "$(jq -r '.allocMB' <<< "$2")" \
    "$(jq -r '.npkgs' <<< "$2")" \
    "$(jq -r '.libs' <<< "$2")" \
    "$(jq -r '.modsys' <<< "$2")" \
    "$(jq -r '.cpu' <<< "$2")" \
    "$3"
}

measureTarget() {
  local kind="$1" name="$2"
  local attr safe prev="" prevWall=0
  attr=$(attrPath "$kind" "$name")
  safe=$(printf '%s' "$kind-$name" | tr -c 'A-Za-z0-9._@-' '_')

  echo
  echo "## $attr"
  header

  local stage
  for stage in shallow config packages toplevel; do
    local expr statsFile start end wallMs metrics
    expr=$(stageExpr "$kind" "$stage")
    statsFile="$tmp/$safe.$stage.json"
    start=$(date +%s%N)
    if ! NIX_SHOW_STATS=1 NIX_COUNT_CALLS=1 NIX_SHOW_STATS_PATH="$statsFile" \
      nixEval "$flake#$attr" --apply "$expr" --json > /dev/null 2> "$tmp/err.log"; then
      echo "warning: $attr stage '$stage' failed to evaluate:" >&2
      tail -5 "$tmp/err.log" >&2
      continue
    fi
    end=$(date +%s%N)
    wallMs=$(((end - start) / 1000000))
    metrics=$(jq "$extract" "$statsFile")
    row "$stage" "$metrics" "$(jq -n --argjson w "$wallMs" '($w / 100 | round) / 10')"
    if [ -n "$prev" ]; then
      local delta
      delta=$(jq -n --argjson a "$metrics" --argjson b "$prev" \
        '$a | with_entries(.key as $k | .value = (($a[$k] - $b[$k]) * 10 | round) / 10)')
      row "  Δ $stage" "$delta" \
        "$(jq -n --argjson w "$((wallMs - prevWall))" '($w / 100 | round) / 10')"
    fi
    prev="$metrics"
    prevWall="$wallMs"
    if [ -n "$outDir" ]; then
      cp "$statsFile" "$outDir/$safe.$stage.json"
    fi
  done

  if [ "$flamegraph" -eq 1 ]; then
    local fgFile="$outDir/$safe.folded"
    echo "capturing flamegraph for $attr -> $fgFile" >&2
    nixEval "$flake#$attr" \
      --apply "$(stageExpr "$kind" toplevel)" \
      --eval-profiler flamegraph --eval-profile-file "$fgFile" \
      --json > /dev/null || echo "warning: flamegraph capture failed for $attr" >&2
  fi
}

echo "eval-weight report for flake: $flake"
echo "(* cpu/wall are informational: machine- and load-dependent)"
resolveTargets | while IFS=$'\t' read -r kind name; do
  measureTarget "$kind" "$name"
done
if [ -n "$outDir" ]; then
  echo
  echo "raw per-stage stats written to: $outDir"
fi
