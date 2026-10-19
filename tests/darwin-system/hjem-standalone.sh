#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Applies the hjem configuration `standaloneHjem` of tests/darwin-system
# on a macOS machine with `hjem standalone switch`, as the user
# `runner`, and checks the launchd agent `org.caisson.profiles` that
# caisson adds to its files:
#
# - once launchd loads the agent, as it does at login, the agent
#   activates the profile of the nvf configuration `standalone-editor`;
# - after the profile is changed by hand, the next
#   `hjem standalone switch` puts it back.
#
# The argument is the output of the check `darwin-system`, which holds
# the manifest and the hjem CLI under `hjem-standalone`. The workflow
# runs this script on its macOS runner, where `runner` is logged in.
set -euo pipefail

out="$1"
hjem="$out/hjem-standalone/hjem/bin/hjem"
manifest="$out/hjem-standalone/manifest.json"
profile="$HOME/.local/state/caisson/profiles/nvf/standalone-editor"
agent="$HOME/Library/LaunchAgents/org.caisson.profiles.plist"

# Waits up to a minute for the profile to hold a Neovim.
wait_for_profile() {
  for _ in $(seq 60); do
    if [ -x "$profile/bin/nvim" ]; then
      return 0
    fi
    sleep 1
  done
  echo "the profile $profile holds no nvim" >&2
  exit 1
}

unset XDG_STATE_HOME

"$hjem" standalone switch --manifest "$manifest"
test -f "$agent"

# The switch that first adds the agent leaves loading it to the next
# login; loading it here is what a login does.
launchctl bootstrap "gui/$(id -u)" "$agent"
wait_for_profile
declared="$(readlink -f "$profile")"

# A profile changed by hand is put back by the next switch.
nix-env --profile "$profile" --set "$out/hjem-standalone/hjem"
if [ -e "$profile/bin/nvim" ]; then
  echo "changing the profile by hand left nvim in it" >&2
  exit 1
fi
"$hjem" standalone switch --manifest "$manifest"
wait_for_profile
restored="$(readlink -f "$profile")"
if [ "$restored" != "$declared" ]; then
  echo "the profile is $restored, not $declared" >&2
  exit 1
fi

launchctl bootout "gui/$(id -u)/org.caisson.profiles"
echo "the launchd agent activates the profile at load and at each switch"
