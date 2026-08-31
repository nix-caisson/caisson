# SPDX-License-Identifier: MIT
# The kernel lives in caisson-core; this path re-exports the vendored
# copy so in-repo references (including eval-weight's by-path import)
# stay stable.
import ../../vendor/caisson-core/lib/kernel/call-flake.nix
