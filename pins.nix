# SPDX-License-Identifier: MIT
#
# caisson's hidden pins: the three trees its own evaluation composes
# with, fetched lazily from flake.nix. Deliberately not flake inputs:
# consumers' locks never carry them, and they cannot be moved with
# `follows`. A downstream that cares which caisson-core (or base
# library, or flake-parts) composes its library declares its own
# inputs and calls that core's mkLib directly, registering caisson's
# exported overlays and modules; such a composition never forces
# these fetches.
#
# Refresh: `nix flake prefetch github:<owner>/<repo>/<rev>` prints
# the revision and NAR hash; tests/dependencies pins the same worlds
# for the test flakes.
{
  caisson-core = {
    owner = "nix-caisson";
    repo = "caisson-core";
    rev = "f0670d3a2419bfa603fc7041ce77d8915ecbb915";
    narHash = "sha256-smVchmdqGUAwe6lw4hUjWTdmvPKa1ePPEkk6piyFWps=";
  };
  # The base library: the nixpkgs.lib mirror (nixpkgs' lib directory
  # published on its own, a small fetch; the lib sits under /lib).
  nixpkgs-lib = {
    owner = "nix-community";
    repo = "nixpkgs.lib";
    rev = "596e2e3940e09b2abbeb03f75fa1828c57fcd72c";
    narHash = "sha256-DTQSMxzDWmT0zhguthvegnVkn7CFqGCv4IHCzk5ZUpM=";
  };
  flake-parts = {
    owner = "hercules-ci";
    repo = "flake-parts";
    rev = "17c9d6cdfc60c64f4ee8d306f9bc0b4ccb51481e";
    narHash = "sha256-vp6Y/Grm98ESt6ceOkWiHWyZRDV3J1RID4w+6NWK9yA=";
  };
}
