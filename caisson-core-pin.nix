# SPDX-License-Identifier: MIT
#
# The caisson-core pin for the lazy fetch in flake.nix. Deliberately
# not a flake input: consumers' locks never carry it, and it cannot
# be moved with `follows`. A downstream that cares which caisson-core
# composes its library declares its own caisson-core input and calls
# that core's mkLib directly, registering caisson's exported overlays
# and modules; such a composition never forces this fetch.
#
# Refresh: `nix flake prefetch github:nix-caisson/caisson-core`
# prints the revision and NAR hash; tests/dependencies pins the same
# revision for the test world, and CI holds the two together.
{
  rev = "f0670d3a2419bfa603fc7041ce77d8915ecbb915";
  narHash = "sha256-smVchmdqGUAwe6lw4hUjWTdmvPKa1ePPEkk6piyFWps=";
}
