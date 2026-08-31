# SPDX-License-Identifier: MIT
# Eval-weight measurement harness. Runs a pinned Nix evaluator inside a
# derivation sandbox against explicitly wired inputs, captures the
# NIX_SHOW_STATS counters, and (optionally) gates the deterministic ones
# against a committed baseline. Thunk/value/env/allocation counts are
# reproducible for a fixed lock set and Nix version; CPU and wall-clock
# time are machine-dependent, so they are always reported but not gated.
{ lib }:
let

  gatedMetricsDefault = [
    "nrThunks"
    "nrValues"
    "nrEnvs"
    "nrFunctionCalls"
    "nrPrimOpCalls"
    "totalAllocBytes"
    "nixpkgsEvals"
    "nixpkgsLibEvals"
    "moduleSystemEvals"
  ];

  # Small-integer counters where a single extra occurrence *is* the
  # regression (one more full nixpkgs instantiation, say). These are gated
  # exactly: no growth allowance, no slack.
  exactMetricsDefault = [
    "nixpkgsEvals"
    "nixpkgsLibEvals"
    "moduleSystemEvals"
  ];

  # Flatten the NIX_SHOW_STATS json into a canonical metric set. The first
  # group is deterministic; cpuSeconds/gcHeapBytes/wallMs are informational.
  #
  # The last three are semantic counters derived from NIX_COUNT_CALLS'
  # per-position call counts, keyed by stable anchors rather than line
  # numbers (which shift between nixpkgs revs):
  # - nixpkgsEvals: calls of the top-level lambda of
  #   pkgs/top-level/default.nix, one per full nixpkgs instantiation.
  # - nixpkgsLibEvals: calls of makeExtensible' in lib/default.nix, one
  #   per nixpkgs-lib bootstrap (the import cache dedups repeat imports of
  #   the same source, so this counts distinct lib sources evaluated).
  # - moduleSystemEvals: calls of evalModules in lib/modules.nix,
  #   including submodule evaluations.
  extractJq = ''
    {
      nrThunks: .nrThunks,
      nrValues: .values.number,
      nrEnvs: .envs.number,
      nrFunctionCalls: .nrFunctionCalls,
      nrPrimOpCalls: .nrPrimOpCalls,
      totalAllocBytes: .gc.totalBytes,
      nixpkgsEvals: ([(.functions // [])[]
        | select((.file // "" | endswith("pkgs/top-level/default.nix"))
                 and .column == 1 and .name == null)
        | .count] | add // 0),
      nixpkgsLibEvals: ([(.functions // [])[]
        | select((.file // "" | endswith("/lib/default.nix"))
                 and (.name // "" | startswith("makeExtensible")))
        | .count] | add // 0),
      moduleSystemEvals: ([(.functions // [])[]
        | select((.file // "" | endswith("/lib/modules.nix"))
                 and .name == "evalModules")
        | .count] | add // 0),
      valueBytes: .values.bytes,
      envBytes: .envs.bytes,
      setBytes: .sets.bytes,
      listBytes: .list.bytes,
      symbolCount: .symbols.number,
      cpuSeconds: .cpuTime,
      gcHeapBytes: .gc.heapSize
    }
  '';

in
{

  callFlake = import ../../../vendor/caisson-core/lib/kernel/call-flake.nix;

  # Build a check derivation that measures one or more eval scenarios and
  # gates deterministic metrics against a baseline.
  #
  # scenarios: { <name> = { entry = <path>; args ? { }; }; }
  #   `entry` is imported inside the sandbox and applied to `args` (store
  #   paths survive as absolute-path strings); the resulting value is
  #   forced strictly, so the entry decides exactly what evaluation gets
  #   measured. Entries must be self-contained files (they may import
  #   call-flake.nix from a caisson store path passed in `args`).
  #
  # gates: list of { name; scenario; } or { name; minuend; subtrahend; }.
  #   A subtraction gate measures the difference between two scenarios,
  #   which isolates framework overhead from the (much larger, churny)
  #   cost of the underlying ecosystem: a 2x regression in framework
  #   machinery is invisible in a whole-nixpkgs total but obvious in the
  #   delta. Defaults to one gate per scenario.
  #
  # baseline: { <gateName> = { <metric> = <int>; }; } or null.
  #   null runs in measure-only bootstrap mode: metrics are printed
  #   (including a paste-ready baseline) and the check passes.
  mkCheck =
    {
      pkgs,
      name,
      scenarios,
      gates ? map (n: {
        name = n;
        scenario = n;
      }) (builtins.attrNames scenarios),
      baseline ? null,
      # Allowed growth over baseline before failing, e.g. 0.10 = 10%.
      maxGrowth ? 0.10,
      # Shrinkage below baseline that logs a "tighten the baseline" note.
      staleShrinkage ? 0.10,
      # Flat allowance added to every ceiling/floor, absorbing byte-level
      # noise from e.g. store path name lengths.
      absSlack ? 4096,
      gatedMetrics ? gatedMetricsDefault,
      # Subset of gatedMetrics compared exactly (growth/slack ignored).
      exactMetrics ? exactMetricsDefault,
      nix ? pkgs.nix,
    }:
    let
      mkSubject =
        scenarioName: scenario:
        pkgs.writeText "eval-weight-${name}-${scenarioName}-subject.nix" ''
          import ${scenario.entry} (builtins.fromJSON (builtins.readFile ${
            pkgs.writeText "eval-weight-${name}-${scenarioName}-args.json" (
              builtins.toJSON (scenario.args or { })
            )
          }))
        '';
      resolvedGates = map (
        g:
        {
          maxGrowth = g.maxGrowth or maxGrowth;
          staleShrinkage = g.staleShrinkage or staleShrinkage;
          absSlack = g.absSlack or absSlack;
        }
        // g
      ) gates;
    in
    pkgs.runCommand "eval-weight-${name}"
      {
        nativeBuildInputs = [
          nix
          pkgs.jq
        ];
        scenariosJson = builtins.toJSON (builtins.mapAttrs (n: s: "${mkSubject n s}") scenarios);
        gatesJson = builtins.toJSON resolvedGates;
        baselineJson = if baseline == null then "" else builtins.toJSON baseline;
        gatedJson = builtins.toJSON gatedMetrics;
        exactJson = builtins.toJSON exactMetrics;
        passAsFile = [
          "scenariosJson"
          "gatesJson"
          "baselineJson"
          "gatedJson"
          "exactJson"
        ];
      }
      ''
        export HOME="$TMPDIR"
        # The sandbox's /nix/store is read-only; forcing drvPaths needs a
        # writable store, so relocate physical writes while keeping the
        # virtual store dir (and therefore all hashes) unchanged.
        export NIX_REMOTE="local?root=$TMPDIR/nix-root"
        mkdir -p "$out/scenarios"

        echo "eval-weight [$name]"
        echo "(cpuSeconds/wallMs vary by machine, so they are reported but not gated)"

        for scenario in $(jq -r 'keys[]' "$scenariosJsonPath"); do
          subject=$(jq -r --arg s "$scenario" '.[$s]' "$scenariosJsonPath")
          start_ns=$(date +%s%N)
          NIX_SHOW_STATS=1 NIX_COUNT_CALLS=1 NIX_SHOW_STATS_PATH="$TMPDIR/raw.json" \
            nix-instantiate --eval --strict --quiet --show-trace "$subject" \
            > "$TMPDIR/value.out"
          end_ns=$(date +%s%N)
          wall_ms=$(( (end_ns - start_ns) / 1000000 ))
          jq '${extractJq} + { wallMs: '"$wall_ms"' }' "$TMPDIR/raw.json" \
            > "$out/scenarios/$scenario.json"
          echo
          echo "scenario [$scenario]:"
          jq -r 'to_entries[] | "  \(.key): \(.value)"' "$out/scenarios/$scenario.json"
        done

        gatedFilter=$(jq -c '[.[]] | map({key: ., value: true}) | from_entries' "$gatedJsonPath")
        echo '{}' > "$out/gates.json"
        while IFS= read -r gate; do
          gname=$(jq -r '.name' <<< "$gate")
          gscenario=$(jq -r '.scenario // empty' <<< "$gate")
          if [ -n "$gscenario" ]; then
            value=$(jq --argjson gated "$gatedFilter" \
              'with_entries(select($gated[.key] == true))' \
              "$out/scenarios/$gscenario.json")
          else
            minuend=$(jq -r '.minuend' <<< "$gate")
            subtrahend=$(jq -r '.subtrahend' <<< "$gate")
            value=$(jq --argjson gated "$gatedFilter" -n \
              --slurpfile a "$out/scenarios/$minuend.json" \
              --slurpfile b "$out/scenarios/$subtrahend.json" \
              '$a[0] | with_entries(select($gated[.key] == true))
                     | with_entries(.key as $k | .value = (.value - $b[0][$k]))')
          fi
          jq --arg g "$gname" --argjson v "$value" '.[$g] = $v' "$out/gates.json" \
            > "$TMPDIR/gates.json.tmp"
          mv "$TMPDIR/gates.json.tmp" "$out/gates.json"
        done < <(jq -c '.[]' "$gatesJsonPath")

        echo
        echo "gate values (deterministic; paste-ready baseline):"
        jq . "$out/gates.json"

        if [ ! -s "$baselineJsonPath" ]; then
          echo
          echo "NO BASELINE SET: measure-only mode, check passes."
          echo "Commit the gate values above as the baseline to start gating."
          exit 0
        fi

        fail=0
        stale=0
        while IFS= read -r gate; do
          gname=$(jq -r '.name' <<< "$gate")
          growth=$(jq -r '.maxGrowth' <<< "$gate")
          shrink=$(jq -r '.staleShrinkage' <<< "$gate")
          slack=$(jq -r '.absSlack' <<< "$gate")
          for metric in $(jq -r '.[]' "$gatedJsonPath"); do
            base=$(jq -r --arg g "$gname" --arg m "$metric" \
              '.[$g][$m] // empty' "$baselineJsonPath")
            [ -n "$base" ] || continue
            actual=$(jq -r --arg g "$gname" --arg m "$metric" \
              '.[$g][$m]' "$out/gates.json")
            if jq -e --arg m "$metric" 'index($m) != null' "$exactJsonPath" > /dev/null; then
              ceiling=$base
              floor=$base
            else
              ceiling=$(jq -n --argjson b "$base" --argjson g "$growth" \
                --argjson s "$slack" '(($b * (1 + $g)) | floor) + $s')
              floor=$(jq -n --argjson b "$base" --argjson g "$shrink" \
                --argjson s "$slack" '(($b * (1 - $g)) | floor) - $s')
            fi
            if [ "$actual" -gt "$ceiling" ]; then
              echo "FAIL [$gname] $metric = $actual exceeds ceiling $ceiling (baseline $base)"
              fail=1
            elif [ "$actual" -lt "$floor" ]; then
              echo "note [$gname] $metric = $actual is well below baseline $base; consider tightening"
              stale=1
            fi
          done
        done < <(jq -c '.[]' "$gatesJsonPath")

        if [ "$fail" -ne 0 ]; then
          echo
          echo "Eval weight regressed. If this is intentional, replace the"
          echo "committed baseline with the gate values printed above."
          exit 1
        fi
        [ "$stale" -eq 0 ] || echo "(baseline is loose but within budget; check passes)"
        echo "eval weight within budget"
      '';

  # A shell tool that measures live flake attributes on the current
  # machine in staged passes and reports where the evaluation weight goes.
  # This is an information producer, not a test: numbers (especially the
  # cpu/wall columns) are only comparable on the same machine and store.
  mkReportApp =
    {
      pkgs,
      name ? "eval-weight-report",
      nix ? pkgs.nix,
    }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [
        nix
        pkgs.jq
      ];
      text = builtins.readFile ./report.sh;
    };

}
