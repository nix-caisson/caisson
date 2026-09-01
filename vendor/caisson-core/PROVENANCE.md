# Vendored caisson-core

Source: https://github.com/nix-caisson/caisson-core
Revision: 7ad01396e6b56b8db584c6b509a81f4904f48d5c (maint: prepare for publication)
NarHash: sha256-3r/rwEziAquGPzbCEvzJu+CX3OG+kVwZzHq+6XwQa7M=
Contents: `lib/` (composition and the kernel) and `vendor/`
(its patched flake-compat), copied verbatim. MIT, like this
repository; the flake-compat copy carries its own license and
provenance header.

Why vendored rather than fetched: caisson composes its own library
through this copy, and the eval-weight and nix-unit harnesses
re-evaluate the tree inside build sandboxes, which have no network
and a fresh store database, so a fetch there fails no matter how the
reference is locked. The copy is a verified pin instead: CI diffs it
against the revision above (checked out from the public repository),
so drift from the pin fails the build. caisson-compat additionally
pins both repositories at their tips and tests them together, which
catches drift between this pin and caisson-core's main.

To refresh: copy `lib/` and `vendor/` from a caisson-core checkout
over this directory and update the revision and NAR hash above
(`nix flake prefetch github:nix-caisson/caisson-core/<rev>` prints
the hash).
