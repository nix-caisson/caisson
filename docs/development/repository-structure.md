# Repository structure

The caisson family is two repositories, with the boundary drawn along
the churn gradient rather than domain lines: each repository's rate of
change is part of its contract.

| Repository | Moves | Holds |
|---|---|---|
| [caisson-core](https://github.com/nix-caisson/caisson-core) | rarely (frozen contract) | keyed composition (`compose`, `resolve`) and the library lifecycle (`mkLib`, registration, the manifest) |
| caisson (this repository) | at ecosystem speed | the integrations, the pkgs-dependent tooling, and the pinned-world suite with its pins |

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
contributing its `lib.caisson` namespace, registering its module
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

## The pinned world

The upstream world caisson is tested against (nixpkgs, home-manager,
colmena, terranix, system-manager, and the test tooling) is pinned in
`tests/dependencies/flake.lock`, a lock only the checks and formatter
partitions read, so caisson's `flake.nix` carries no churning pin. The
pinned-world suite, `tests/pinned-world`, composes caisson with those
pins and exercises it end to end; it is the `pinned-world` check, so a
pull request is judged against the last known good world, and a
change to caisson lands with the probe changes it needs in the same
commit.

Drift is detected separately. The `drift` workflow runs daily on
`main`, advances the pins in the working tree without committing, and
builds the suite check against today's upstreams. A red run means an
upstream moved and broke an expectation caisson holds; the committed
pins are the last known good and move in the commit that fixes it.
The README badge reports that run.

The suite lived in a third repository, caisson-compat, whose lock
pinned caisson; the stable repositories fetched it at HEAD and ran it
with `--override-input`. A breaking change to caisson then needed a
companion change there that could not be green until caisson had
landed, so the suite moved here.
