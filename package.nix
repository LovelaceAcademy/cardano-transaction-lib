{ ps-pkgs, ps-pkgs-ns, ... }:
let npmlock2nix = (import
  (fetchGit {
    url = "https://github.com/nix-community/npmlock2nix.git";
    rev = "5c4f247688fc91d665df65f71c81e0726621aaa8";
  })
  { });
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
  foreign.Main.node_modules = npmlock2nix.node_modules { src = ./.; } + /node_modules;
}
