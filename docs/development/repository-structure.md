# Repository structure

caisson is split into two repositories, with the boundary drawn along
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
library lifecycle: `mkLib` is the point of caisson-core. It takes the base
library as a plain argument (nothing is looked up by input name) and
injects the machinery, the class-keyed module registry, and the
manifest under the composed library's `caisson-core` namespace. Its
contract is intended to freeze: consumers should be able to pin it and
not think about the pin again. Anyone who wants overlay composition
without nixpkgs can depend on it directly.

## caisson

The layer users reach for: the integrations (`structural`,
`flake-parts`, `nixpkgs`, `nixos`, `nixos-minimal`, `nixos-test`, `nix-unit`, `home-manager`,
`home-manager-minimal`, `darwin`, `hjem`, `caisson-colmena`, `colmena`,
`caisson-disko`, `disko`, `caisson-facter`, `facter`,
`caisson-microvm`, `microvm`, `caisson-nixops4-composite`,
`caisson-nixops4-resource`, `nixops4`,
`terranix`, `system-manager`, `treefmt`,
`nvf`, `nixvim`, `nemacs`, `topology`, `kubenix`, `nixidy`), each
a library overlay
contributing its `lib.caisson` namespace, registering its module
class where it has a class (`nixos-minimal` and `home-manager-minimal`
each evaluate a class another integration
owns and carry constructors only, and `microvm` evaluates the `nixos`
class as configurations of a separate type), and taking its ecosystem as an `ecosystemSrc` argument
resolved from the declarations of the mkLib call that composes it
(including flake-parts: the integration calls the consumer's flake-parts source
with the composed library as its `nixpkgs-lib`, and carries the
export machinery that writes a composition's manifest into flake
outputs). The pkgs-dependent tooling (`eval-weight`,
`mkMemoizedDerivationRead`) lives here too. The flake of caisson
declares the inputs caisson-core, nixpkgs-lib and flake-parts,
used when caisson itself is evaluated; a consumer's evaluation reads none of them,
since every ecosystem comes from the consumer's declarations, and a
consumer that composes with caisson-core directly registers
caisson's exported overlays and modules. Hand-wired evaluations (the
sandboxed test harnesses, which receive every source tree as an argument)
inject the same names beside `self`.

## The pinned world

The upstream world caisson is tested against (nixpkgs, home-manager,
colmena, disko, nix-darwin, hjem, terranix, system-manager, microvm.nix, and the test
tooling) is pinned in
`tests/dependencies/flake.lock`, a lock that only the checks
configuration (`configs/flake/checks`) and the formatter partition read,
so caisson's `flake.nix` carries no churning pin. Where that lock names a
dependency that `flake.lock` pins as well (caisson-core, flake-parts,
nixpkgs-lib), the checks use the pin of `flake.lock`. The
pinned-world suite, `tests/pinned-world`, composes caisson with those
pins and exercises it end to end; it is the `pinned-world` check, so a
pull request is judged against the last known good world, and a
change to caisson lands with the probe changes it needs in the same
commit.

Drift is detected separately. The `drift` workflow runs daily on
`main`, advances the pins of `tests/dependencies/flake.lock` and the pins
of caisson-core, flake-parts and nixpkgs-lib in `flake.lock` in the
working tree without committing, and builds the suite check against
today's upstreams. A red run means an
upstream moved and broke an expectation caisson holds; the committed
pins are the last known good and move in the commit that fixes it.
The README badge reports that run.
