# Repository structure

The caisson family is three repositories, with boundaries drawn along
churn gradients rather than domain lines: each repository's rate of
change is part of its contract.

| Repository | Moves | Holds |
|---|---|---|
| [caisson-core](https://github.com/nix-caisson/caisson-core) | rarely (frozen contract) | keyed composition (`compose`, `resolve`) and the library lifecycle (`mkLib`, registration, the manifest) |
| caisson (this repository) | at ecosystem speed | the seven integrations (flake-parts included) and the pkgs-dependent tooling |
| [caisson-compat](https://github.com/nix-caisson/caisson-compat) | at upstream speed | pinned-world tests and compatibility exports |

## caisson-core

The foundation. A zero-input flake whose library code references
nothing but builtins (CI enforces this with a lint), holding
`compose`, `resolve`, and the
library lifecycle: `mkLib` is the point of core. It takes the base
library as a plain argument (nothing is looked up by input name) and
injects the machinery, the class-keyed module registry, and the
manifest under the composed library's `caisson-core` namespace. Its
contract is intended to freeze: consumers should be able to pin it and
not think about the pin again. Anyone who wants overlay composition
without nixpkgs can depend on it directly.

## caisson

The layer users reach for: the seven integrations (`flake-parts`,
`nixpkgs`, `nixos`, `home-manager`, `colmena`, `terranix`,
`system-manager`), each a library overlay contributing its
`lib.caisson` namespace, registering its own module class where it
has one, and taking its ecosystem as an explicit
`ecosystemSrc` argument (flake-parts is the exception: its pin is
caisson's own hidden input, and it carries the export machinery that
projects a composition's manifest into flake outputs). The
pkgs-dependent tooling (`eval-weight`,
`mkMemoizedDerivationRead`) lives here too. caisson's own flake
composes with the vendored caisson-core (under
`vendor/caisson-core` while the repositories are private; the copy's
PROVENANCE.md carries the revision and refresh ritual, and
caisson-compat pins both repositories and catches drift between the
copy and caisson-core's main). caisson also exports its library
contributions, integrations included, as keyed entries via
`lib.composition.entriesFor`.

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
