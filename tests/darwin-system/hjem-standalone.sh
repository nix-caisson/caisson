#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Applies the hjem configuration `standaloneHjemOf` of
# tests/darwin-system on a macOS machine with `hjem standalone switch`,
# as the user `runner`, through a sequence of changes, and checks the
# launchd agent `org.caisson.profiles` that caisson adds to its files.
# The Neovim of v2 has `vim`, the Neovim of v1 has not.
#
# - v1 is applied, and once launchd loads the agent, as it does at
#   login, the agent activates the profile of the nvf configuration
#   `standalone-editor` in v1;
# - a switch to v2 activates v2, with the agent launchd loaded from v1;
# - `hjem standalone rollback` activates v1;
# - after the profile is changed by hand, a switch to v1 puts it back.
#
# The argument is the output of the check `darwin-system`, which holds
# the manifests and the hjem CLI under `hjem-standalone`. The workflow
# runs this script on its macOS runner, where `runner` is logged in.
set -euo pipefail

out="$1"
hjem="$out/hjem-standalone/hjem/bin/hjem"
profile="$HOME/.local/state/caisson/profiles/nvf/standalone-editor"
agent="$HOME/Library/LaunchAgents/org.caisson.profiles.plist"

fail() {
  echo "$1" >&2
  exit 1
}

# Waits up to a minute for the profile to hold the Neovim of a version.
holds() {
  local version="$1"
  for _ in $(seq 60); do
    if [ -x "$profile/bin/nvim" ]; then
      if [ "$version" = v2 ] && [ -x "$profile/bin/vim" ]; then
        return 0
      fi
      if [ "$version" = v1 ] && [ ! -e "$profile/bin/vim" ]; then
        return 0
      fi
    fi
    sleep 1
  done
  fail "the profile $profile does not hold the Neovim of $version"
}

switch_to() {
  "$hjem" standalone switch --manifest "$out/hjem-standalone/manifest-$1.json"
}

unset XDG_STATE_HOME

switch_to v1
test -f "$agent" || fail "the switch linked no agent at $agent"

# The switch that first adds the agent leaves loading it to the next
# login; loading it here is what a login does.
launchctl bootstrap "gui/$(id -u)" "$agent"
holds v1
declared="$(readlink -f "$profile")"

switch_to v2
holds v2

"$hjem" standalone rollback
holds v1

# A profile changed by hand is put back by the next switch.
nix-env --profile "$profile" --set "$out/hjem-standalone/hjem"
if [ -e "$profile/bin/nvim" ]; then
  fail "changing the profile by hand left nvim in it"
fi
switch_to v1
holds v1
restored="$(readlink -f "$profile")"
[ "$restored" = "$declared" ] || fail "the profile is $restored, not $declared"

launchctl bootout "gui/$(id -u)/org.caisson.profiles"
echo "the launchd agent activates the profile through each switch and the rollback"
