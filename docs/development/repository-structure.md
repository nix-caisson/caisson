# Repository structure

The caisson family is three repositories, with boundaries drawn along
churn gradients rather than domain lines: each repository's rate of
change is part of its contract.

| Repository | Moves | Holds |
|---|---|---|
| [caisson-core](https://github.com/nix-caisson/caisson-core) | rarely (frozen contract) | the composition calculus: `compose`, `resolve` |
| caisson (this repository) | at ecosystem speed | the framework: `mkLib`, `mkFlake`, module classes, integrations |
| [caisson-compat](https://github.com/nix-caisson/caisson-compat) | at upstream speed | pinned-world tests and compatibility exports |

## caisson-core

The engine. A zero-input flake whose library code references nothing
but builtins (CI enforces this with a lint), implementing the
[composition calculus](../concepts/composition-calculus.md). Its
contract is intended to freeze: consumers should be able to pin it and
never think about the pin again. Anyone who wants overlay composition
without nixpkgs can depend on it directly.

## caisson

The layer users reach for. It composes libraries, registers and
exports class-keyed modules, speaks flake-parts, and contains the
integrations (`caisson-nixpkgs`, `caisson-nixos`,
`caisson-home-manager`, `caisson-colmena`, `caisson-terranix`,
`caisson-system-manager`), each a library overlay registering its own
module class and taking its target ecosystem as an explicit
`ecosystemSrc` argument. `mkLib` composes on the caisson-core engine
(vendored under `vendor/caisson-core` while the repositories are
private; the copy's PROVENANCE.md carries the revision and refresh
ritual, and caisson-compat pins both repositories and catches drift
between the copy and caisson-core's main). caisson also exports its
library contributions, integrations included, in keyed calculus form
via `lib.composition.entriesFor`.

## caisson-compat

The churn quarantine. caisson-compat pins concrete versions of
everything: caisson, caisson-core, and the upstream world (nixpkgs
lib, flake-parts). Two audiences use it:

- **Consumers outside the caisson ecosystem** depend on caisson-compat
  and get ordinary, follows-overridable pins that track upstream.
- **The stable repositories test through it.** Their CI fetches
  caisson-compat and runs its suite with `--override-input` pointing
  back at the local working tree, so a change to caisson or
  caisson-core is exercised against the pinned world without either
  stable repository carrying churning pins of its own.

Because compat's routine job is advancing its pins, its update runs
double as drift detection: a pin advance that fails against the
current stable repositories signals an upstream evaluation-shape
change that caisson must absorb. The stable repositories rev on those
events, not on a schedule.

While the repositories are private, cross-repository fetches in CI
need the `CAISSON_CI_SSH_KEY` secret (an SSH key able to read the
nix-caisson repositories); jobs without it skip with a notice.
caisson-compat runs on push, pull request, weekly schedule (the pin
advance that doubles as drift detection, auto-landed when green), and
manual dispatch, and the stable repositories carry non-blocking
`compat-suite` jobs under the same gate. At publication the secret
becomes unnecessary.
