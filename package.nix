{ ps-pkgs, ps-pkgs-ns, pkgs, ... }:
let
  bpPackage = fetchGit {
    url = "https://github.com/serokell/nix-npm-buildpackage.git";
    rev = "cab951dd024dd367511d48440de6f93664ee35aa";
  };
  bp = pkgs.callPackage bpPackage { };
in
with ps-pkgs;
with ps-pkgs-ns.lovelaceAcademy;
{
  version = "2.0.0";
  dependencies =
    [
      aeson
      aeson-helpers
      aff
      aff-promise
      aff-retry
      affjax
      arraybuffer-types
      arrays
      bifunctors
      bigints
      checked-exceptions
      console
      const
      contravariant
      control
      datetime
      debug
      effect
      either
      encoding
      enums
      exceptions
      foldable-traversable
      foreign
      foreign-object
      heterogeneous
      http-methods
      identity
      integers
      js-date
      lattice
      lists
      math
      maybe
      medea
      media-types
      monad-logger
      mote
      newtype
      node-buffer
      node-child-process
      node-fs
      node-fs-aff
      node-path
      node-process
      node-streams
      nonempty
      now
      numbers
      optparse
      ordered-collections
      orders
      parallel
      partial
      posix-types
      prelude
      profunctor
      profunctor-lenses
      purescript-toppokki
      quickcheck
      quickcheck-combinators
      quickcheck-laws
      rationals
      record
      refs
      safe-coerce
      spec
      spec-quickcheck
      strings
      stringutils
      tailrec
      text-encoding
      these
      transformers
      tuples
      typelevel
      typelevel-prelude
      uint
      undefined
      unfoldable
      untagged-union
      variant
    ];
  foreign.Main.node_modules = bp.buildNpmPackage
    {
      src = ./.;
      #npmBuild = "echo 'skipping build'";
    };
}
