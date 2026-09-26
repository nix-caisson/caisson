# Repository structure

The caisson family is three repositories, with boundaries drawn along
churn gradients rather than domain lines: each repository's rate of
change is part of its contract.

| Repository | Moves | Holds |
|---|---|---|
| [caisson-core](https://github.com/nix-caisson/caisson-core) | rarely (frozen contract) | keyed composition (`compose`, `resolve`) and the library lifecycle (`mkLib`, registration, the manifest) |
| caisson (this repository) | at ecosystem speed | the integrations and the pkgs-dependent tooling |
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

The layer users reach for: the integrations (`structural`,
`flake-parts`, `nixpkgs`, `nixos`, `nixos-minimal`, `home-manager`,
`home-manager-minimal`, `colmena`, `terranix`, `system-manager`), each
a library overlay
contributing its `lib.caisson` namespace, registering its own module
class where it has one (`nixos-minimal` and `home-manager-minimal`
each evaluate a class another integration
owns and carry constructors only), and taking its ecosystem as an `ecosystemSrc` argument
resolved from the declarations of the mkLib call that composes it
(including flake-parts: the integration calls the consumer's flake-parts source
with the composed library as its `nixpkgs-lib`, and carries the
export machinery that projects a composition's manifest into flake
outputs). The pkgs-dependent tooling (`eval-weight`,
`mkMemoizedDerivationRead`) lives here too. The flake of caisson
declares the inputs caisson-core, nixpkgs-lib and flake-parts,
used when caisson itself is evaluated; a consumer's evaluation reads none of them,
since every ecosystem comes from the consumer's declarations, and a
consumer that composes with caisson-core directly registers
caisson's exported overlays and modules. Hand-wired evaluations (the
sandboxed test harnesses, which receive every tree as an argument)
inject the same names beside `self`.

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

All three repositories are public, so cross-repository fetches in CI
need no credential. caisson-compat runs on push, pull request,
weekly schedule (the pin advance that doubles as drift detection,
auto-landed when green), and manual dispatch, and the stable
repositories carry non-blocking `compat-suite` jobs that fetch
compat at HEAD and override their own pin with the working tree.
