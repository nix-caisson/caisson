#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Activates the macOS machine `runnerMachineOf` of tests/darwin-system
# on a macOS machine, through a sequence of changes, and checks after
# each step the profile of the system, the file of the hjem
# configuration of `runner` and the profile inside it. The Neovims of v2
# have `vim`, those of v1 have not, and the file names the version.
#
# - v1 is activated: everything is v1;
# - v2 is activated: everything is v2;
# - v1 is activated again: everything is v1;
# - the profile of `runner` and the profile of the system are changed by
#   hand, and activating v1 again puts the profiles back.
#
# The argument is the output of the check `darwin-system`, which holds
# the systems of the machine under `runner-machine`. The workflow runs
# this script on its macOS runner, as the logged-in user `runner`, who
# may use `sudo`. Activating changes the runner: it is a machine the
# workflow discards.
set -euo pipefail

out="$1"
system_profile="/nix/var/nix/profiles/caisson/nvf/editor"
user_profile="$HOME/.local/state/caisson/profiles/nvf/hjem-editor"
file="$HOME/.config/probe/version"

fail() {
  echo "$1" >&2
  exit 1
}

# Waits up to a minute for the profile at `$1` to hold the Neovim of the
# version `$2`. hjem's agent and the activation of the profiles of
# `runner` run after the activation of the machine returns.
holds() {
  local path="$1" version="$2"
  for _ in $(seq 60); do
    if [ -x "$path/bin/nvim" ]; then
      if [ "$version" = v2 ] && [ -x "$path/bin/vim" ]; then
        return 0
      fi
      if [ "$version" = v1 ] && [ ! -e "$path/bin/vim" ]; then
        return 0
      fi
    fi
    sleep 1
  done
  fail "the profile $path does not hold the Neovim of $version"
}

# Waits up to a minute for the file of `runner` to name the version.
has_file() {
  for _ in $(seq 60); do
    if [ "$(cat "$file" 2>/dev/null || true)" = "$1" ]; then
      return 0
    fi
    sleep 1
  done
  fail "$file does not name $1"
}

is_at() {
  holds "$system_profile" "$1"
  holds "$user_profile" "$1"
  has_file "$1"
}

activate() {
  sudo "$out/runner-machine/$1/activate"
}

# nix-darwin replaces only the files in /etc it wrote itself; the files
# of macOS it would replace are renamed first, as its message asks.
while IFS= read -r -d '' link; do
  sub="${link#"$out/runner-machine/v1/etc/"}"
  if [ -e "/etc/$sub" ] && [ "$(readlink "/etc/$sub")" != "/etc/static/$sub" ]; then
    sudo mv "/etc/$sub" "/etc/$sub.before-nix-darwin"
  fi
done < <(find -H "$out/runner-machine/v1/etc" -type l -print0)

activate v1
is_at v1
system_declared="$(readlink -f "$system_profile")"
user_declared="$(readlink -f "$user_profile")"

activate v2
is_at v2

activate v1
is_at v1

# Profiles changed by hand are put back when the machine is activated.
other="$out/runner-machine/v1"
nix-env --profile "$user_profile" --set "$other"
sudo nix-env --profile "$system_profile" --set "$other"
[ ! -e "$user_profile/bin/nvim" ] || fail "changing the profile of runner by hand left nvim in it"
[ ! -e "$system_profile/bin/nvim" ] || fail "changing the profile of the system by hand left nvim in it"
activate v1
is_at v1
[ "$(readlink -f "$system_profile")" = "$system_declared" ] || fail "the profile of the system was not put back"
[ "$(readlink -f "$user_profile")" = "$user_declared" ] || fail "the profile of runner was not put back"

echo "the machine activates its profiles and the hjem configuration of runner through each activation"
