# SPDX-License-Identifier: MIT
# The kernel lives in caisson-core; this path re-exports the vendored
# copy (which routes through caisson-core's patched flake-compat). See
# its header for the semantics and the relative-path coverage
# constraint.
import ../../vendor/caisson-core/lib/kernel/partition-extra-inputs.nix
