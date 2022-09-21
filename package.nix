{ ps-pkgs, ps-pkgs-ns, pkgs, ... }:
let
  npm2nixPkg = fetchGit {
    url = "https://github.com/nix-community/npmlock2nix.git";
    rev = "5c4f247688fc91d665df65f71c81e0726621aaa8";
  };
  npm2nix = pkgs.callPackage npm2nixPkg { };
  node_modules = npm2nix.node_modules { src = ./.; } + /node_modules;
in
with ps-pkgs;
with ps-pkgs-ns;
{
  version = "2.0.0";
  dependencies =
    [
      lovelaceAcademy.aeson
      lovelaceAcademy.aeson-helpers
      aff
      aff-promise
      aff-retry
      affjax
      arraybuffer-types
      arrays
      bifunctors
      lovelaceAcademy.bigints
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
      lovelaceAcademy.lattice
      lists
      math
      maybe
      lovelaceAcademy.medea
      media-types
      monad-logger
      lovelaceAcademy.mote
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
      lovelaceAcademy.purescript-toppokki
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

  # TODO: get all .js files and use their paths to generate foreigns
  # grep -rl require src/{**/*,*}.js | xargs -I _ sh -c "S=_; grep module \${S/js/purs} | cut -d ' ' -f2"
  foreign."BalanceTx.UtxoMinAda".node_modules = node_modules;
  foreign."Deserialization.FromBytes".node_modules = node_modules;
  foreign."Deserialization.Language".node_modules = node_modules;
  foreign."Deserialization.Transaction".node_modules = node_modules;
  foreign."Deserialization.UnspentOutput".node_modules = node_modules;
  foreign."Deserialization.WitnessSet".node_modules = node_modules;
  foreign."Plutip.PortCheck".node_modules = node_modules;
  foreign."Plutip.Utils".node_modules = node_modules;
  foreign."QueryM.UniqueId".node_modules = node_modules;
  foreign."Serialization.Address".node_modules = node_modules;
  foreign."Serialization.AuxiliaryData".node_modules = node_modules;
  foreign."Serialization.BigInt".node_modules = node_modules;
  foreign."Serialization.Hash".node_modules = node_modules;
  foreign."Serialization.MinFee".node_modules = node_modules;
  foreign."Serialization.NativeScript".node_modules = node_modules;
  foreign."Serialization.PlutusData".node_modules = node_modules;
  foreign."Serialization.PlutusScript".node_modules = node_modules;
  foreign."Serialization.WitnessSet".node_modules = node_modules;
  foreign."Types.BigNum".node_modules = node_modules;
  foreign."Types.Int".node_modules = node_modules;
  foreign."Types.TokenName".node_modules = node_modules;
  foreign."Base64".node_modules = node_modules;
  foreign."Hashing".node_modules = node_modules;
  foreign."JsWebSocket".node_modules = node_modules;
  foreign."Serialization".node_modules = node_modules;
}
