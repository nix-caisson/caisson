# Vendored caisson-core

Source: https://github.com/nix-caisson/caisson-core
Revision: 7ad0139 (maint: prepare for publication)
Contents: `lib/` (composition and the kernel) and `vendor/`
(its patched flake-compat), copied verbatim. MIT, like this
repository; the flake-compat copy carries its own license and
provenance header.

Why vendored rather than pinned: caisson composes its own library
through this copy, and check builds evaluate in sandboxes that
cannot fetch. While the caisson repositories are private no fetchable
reference works there at all; after publication this copy is expected
to become a narHash-pinned lazy fetch. caisson-compat pins both
repositories and tests them together, which is what catches drift
between this copy and caisson-core's main.

To refresh: copy `lib/` and `vendor/` from a caisson-core checkout
over this directory and update the revision above.
