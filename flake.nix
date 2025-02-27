{
  description = "cardano-transaction-lib";

  inputs = {
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    # for the purescript project
    ogmios = {
      url = "github:mlabs-haskell/ogmios/9c04524d45de2c417ddda9e7ab0d587a54954c57";
      inputs = {
        haskell-nix.follows = "haskell-nix";
        nixpkgs.follows = "nixpkgs";
      };
    };

    plutip.url = "github:mlabs-haskell/plutip/8364c43ac6bc9ea140412af9a23c691adf67a18b";
    ogmios-datum-cache.url = "github:mlabs-haskell/ogmios-datum-cache/880a69a03fbfd06a4990ba8873f06907d4cd16a7";
    # Repository with network parameters
    cardano-configurations = {
      # Override with "path:/path/to/cardano-configurations";
      url = "github:input-output-hk/cardano-configurations";
      flake = false;
    };
    easy-purescript-nix = {
      url = "github:justinwoo/easy-purescript-nix/d56c436a66ec2a8a93b309c83693cef1507dca7a";
      flake = false;
    };
    purs-nix.url = "github:LovelaceAcademy/purs-nix";
    npmlock2nix.url = "github:nix-community/npmlock2nix";
    npmlock2nix.flake = false;

    # for the haskell server
    iohk-nix.url = "github:input-output-hk/iohk-nix";
    haskell-nix.follows = "plutip/haskell-nix";
    nixpkgs.follows = "plutip/nixpkgs";
  };

  outputs =
    { self
    , nixpkgs
    , haskell-nix
    , iohk-nix
    , cardano-configurations
    , ...
    }@inputs:
    let
      supportedSystems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      perSystem = nixpkgs.lib.genAttrs supportedSystems;

      mkNixpkgsFor = system: import nixpkgs {
        overlays = nixpkgs.lib.attrValues self.overlays ++ [
          (_: _: {
            ogmios-fixtures = inputs.ogmios;
          })
        ];
        inherit (haskell-nix) config;
        inherit system;
      };

      inherit (import ./nix/runtime.nix { inherit inputs; })
        buildCtlRuntime launchCtlRuntime;

      allNixpkgs = perSystem mkNixpkgsFor;

      nixpkgsFor = system: allNixpkgs.${system};

      buildOgmiosFixtures = pkgs: pkgs.runCommand "ogmios-fixtures"
        {
          buildInputs = [ pkgs.jq pkgs.pcre ];
        }
        ''
          cp -r ${pkgs.ogmios-fixtures}/server/test/vectors vectors
          chmod -R +rwx .

          function on_file () {
            local path=$1
            local parent="$(basename "$(dirname "$path")")"
            if command=$(pcregrep -o1 -o2 -o3 'Query\[(.*)\]|(EvaluateTx)|(SubmitTx)' <<< "$path")
            then
              echo "$path"
              json=$(jq -c .result "$path")
              md5=($(md5sum <<< "$json"))
              printf "%s" "$json" > "ogmios/$command-$md5.json"
            fi
          }
          export -f on_file

          mkdir ogmios
          find vectors/ -type f -name "*.json" -exec bash -c 'on_file "{}"' \;
          mkdir $out
          cp -rT ogmios $out
        '';

      psProjectFor = pkgs:
        let
          projectName = "cardano-transaction-lib";
          # `filterSource` will still trigger rebuilds with flakes, even if a
          # filtered path is modified as the output path name is impurely
          # derived. Setting an explicit `name` with `path` helps mitigate this
          src = builtins.path {
            path = self;
            name = "${projectName}-src";
            filter = path: ftype:
              !(pkgs.lib.hasSuffix ".md" path)
              && !(ftype == "directory" && builtins.elem
                (baseNameOf path) [ "server" "doc" ]
              );
          };
          ogmiosFixtures = buildOgmiosFixtures pkgs;
          project = pkgs.purescriptProject {
            inherit src pkgs projectName;
            packageJson = ./package.json;
            packageLock = ./package-lock.json;
            shell = {
              withRuntime = true;
              shellHook = exportOgmiosFixtures;
              packageLockOnly = true;
              packages = with pkgs; [
                arion
                fd
                haskellPackages.fourmolu
                nixpkgs-fmt
                nodePackages.eslint
                nodePackages.prettier
              ];
            };
          };
          exportOgmiosFixtures =
            ''
              export OGMIOS_FIXTURES="${ogmiosFixtures}"
            '';
        in
        rec {
          packages = {

            ctl-example-bundle-web = project.bundlePursProject {
              main = "Examples.ByUrl";
              entrypoint = "examples/index.js";
            };

            ctl-runtime = pkgs.arion.build {
              inherit pkgs;
              modules = [ (buildCtlRuntime pkgs { }) ];
            };

            docs = project.buildSearchablePursDocs {
              packageName = projectName;
            };

            checks = {
              ctl-plutip-test = project.runPlutipTest {
                name = "ctl-plutip-test";
                testMain = "Test.Plutip";
                # After updating `PlutipConfig` this can be set for now:
                # withCtlServer = false;
                env = { OGMIOS_FIXTURES = "${ogmiosFixtures}"; };
              };
              ctl-unit-test = project.runPursTest {
                name = "ctl-unit-test";
                testMain = "Ctl.Test.Unit";
                env = { OGMIOS_FIXTURES = "${ogmiosFixtures}"; };
              };
            };

            devShell = project.devShell;

            apps = {
              docs = project.launchSearchablePursDocs {
                builtDocs = packages.docs;
              };
            };
          };
        };

      hsProjectFor = pkgs: import ./server/nix {
        inherit inputs pkgs;
        inherit (pkgs) system;
        src = ./server;
      };

      pursNixFor = system:
        let
          purs-nix = inputs.purs-nix { inherit system; };
          pkgs = nixpkgsFor system;
        in
        rec {
          default = lovelaceAcademy;
          lovelaceAcademy = purs-nix.build {
            name = "lovelaceAcademy.cardano-transaction-lib";
            src.path = pkgs.stdenv.mkDerivation {
              name = "ctl";
              src = ./.;
              dontBuild = true;
              installPhase = "mkdir -p $out/src && cp -r {src,examples,test} $out/src";
            };
            info = {
              version = "2.0.0";
              dependencies =
                with purs-nix.ps-pkgs-ns.lovelaceAcademy;
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
                  toppokki
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

              # TODO: compare the bundle produced by purs-nix using embeded w/o embeded runtime deps to test if there are dups and decide if we keep the deps embeded
              # TODO: get all .js files and use their paths to generate foreigns
              # grep -rl require src/{**/*,*}.js | xargs -I _ sh -c "S=_; grep module \${S/js/purs} | cut -d ' ' -f2"
              foreign =
                let
                  ffi = [
                    "BalanceTx.UtxoMinAda"
                    "Deserialization.FromBytes"
                    "Deserialization.Language"
                    "Deserialization.Transaction"
                    "Deserialization.UnspentOutput"
                    "Deserialization.WitnessSet"
                    "Plutip.PortCheck"
                    "Plutip.Utils"
                    "QueryM.UniqueId"
                    "Serialization.Address"
                    "Serialization.AuxiliaryData"
                    "Serialization.BigInt"
                    "Serialization.Hash"
                    "Serialization.MinFee"
                    "Serialization.NativeScript"
                    "Serialization.PlutusData"
                    "Serialization.PlutusScript"
                    "Serialization.WitnessSet"
                    "Types.BigNum"
                    "Types.Int"
                    "Types.TokenName"
                    "Base64"
                    "Hashing"
                    "JsWebSocket"
                    "Serialization"
                  ];
                  node_modules = pkgs.npmlock2nix.node_modules { src = ./.; } + /node_modules;
                in
                pkgs.lib.attrsets.genAttrs ffi (_: { inherit node_modules; });
            };
          };
        };
    in
    {
      overlay = builtins.trace
        (
          "warning: `cardano-transaction-lib.overlay` is deprecated and will be"
          + " removed in the next release. Please use"
          + " `cardano-transaction-lib.overlays.{runtime, purescript, ctl-server}`"
          + " directly instead"
        )
        nixpkgs.lib.composeManyExtensions
        (nixpkgs.lib.attrValues self.overlays);

      overlays = with inputs; {
        purescript = final: prev: {
          easy-ps = import inputs.easy-purescript-nix { pkgs = final; };
          purescriptProject = import ./nix { pkgs = final; };
          npmlock2nix = import npmlock2nix { pkgs = final; };
        };
        # This is separate from the `runtime` overlay below because it is
        # optional (it's only required if using CTL's `applyArgs` effect).
        # Including it by default in the `overlays.runtime` also requires that
        # `prev` include `haskell-nix.overlay` and `iohk-nix.overlays.crypto`;
        # this is not ideal to force upon all users
        ctl-server = nixpkgs.lib.composeManyExtensions [
          (
            final: prev:
              # if `haskell-nix.overlay` has not been applied, we cannot use the
              # package set to build the `hsProjectFor`. We don't want to always
              # add haskell.nix's overlay or use the `ctl-server` from our own
              # `outputs.packages` because this might lead to conflicts with the
              # `hackage.nix` version being used (this might also happen with the
              # Ogmios and Plutip packages, but at least we have direct control over
              # our own haskell.nix project)
              #
              # We can check for the necessary attribute and then apply the
              # overlay if necessary
              nixpkgs.lib.optionalAttrs (!(prev ? haskell-nix))
                (haskell-nix.overlay final prev)

          )
          (
            final: prev:
              # Similarly, we need to make sure that `libsodium-vrf` is available
              # for the Haskell server
              nixpkgs.lib.optionalAttrs (!(prev ? libsodium-vrf))
                (iohk-nix.overlays.crypto final prev)
          )
          (
            final: prev: {
              ctl-server =
                (hsProjectFor final).hsPkgs.ctl-server.components.exes.ctl-server;
            }
          )
        ];
        runtime = nixpkgs.lib.composeManyExtensions [
          (
            final: prev:
              let
                inherit (prev) system;
              in
              {
                plutip-server =
                  inputs.plutip.packages.${system}."plutip:exe:plutip-server";
                ogmios-datum-cache =
                  inputs.ogmios-datum-cache.defaultPackage.${system};
                ogmios = ogmios.packages.${system}."ogmios:exe:ogmios";
                buildCtlRuntime = buildCtlRuntime final;
                launchCtlRuntime = launchCtlRuntime final;
                inherit cardano-configurations;
              }
          )
          (
            final: prev: nixpkgs.lib.optionalAttrs (!(prev ? ctl-server))
              (
                builtins.trace
                  (
                    "Warning: `ctl-server` has moved to `overlays.ctl-server`"
                    + " and will be removed from `overlays.runtime` soon"
                  )
                  (self.overlays.ctl-server final prev)
              )
          )

        ];
      };

      # flake from haskell.nix project
      hsFlake = perSystem (system: (hsProjectFor (nixpkgsFor system)).flake { });

      devShells = perSystem (system: {
        # This is the default `devShell` and can be run without specifying
        # it (i.e. `nix develop`)
        default = (psProjectFor (nixpkgsFor system)).devShell;
        # It might be a good idea to keep this as a separate shell; if you're
        # working on the PS frontend, it doesn't make a lot of sense to pull
        # in all of the Haskell dependencies
        #
        # This can be used with `nix develop .#hsDevShell
        hsDevShell = self.hsFlake.${system}.devShell;
      });

      packages = perSystem (system:
        self.hsFlake.${system}.packages
        // (psProjectFor (nixpkgsFor system)).packages
        // (pursNixFor system)
      );

      apps = perSystem (system:
        let
          pkgs = nixpkgsFor system;
        in
        (psProjectFor pkgs).apps // {
          inherit (self.hsFlake.${system}.apps) "ctl-server:exe:ctl-server";
          ctl-runtime = pkgs.launchCtlRuntime { };
          default = self.apps.${system}.ctl-runtime;
        });

      # TODO
      # Add a check that attempts to verify if the scaffolding template is
      # reasonably up-to-date. See:
      # https://github.com/Plutonomicon/cardano-transaction-lib/issues/839
      checks = perSystem (system:
        let
          pkgs = nixpkgsFor system;
        in
        (psProjectFor pkgs).checks
        // self.hsFlake.${system}.checks
        // {
          formatting-check = pkgs.runCommand "formatting-check"
            {
              nativeBuildInputs = with pkgs; [
                easy-ps.purs-tidy
                haskellPackages.fourmolu
                nixpkgs-fmt
                nodePackages.prettier
                nodePackages.eslint
                fd
              ];
            }
            ''
              cd ${self}
              make check-format
              touch $out
            '';
        });

      check = perSystem (system:
        (nixpkgsFor system).runCommand "combined-check"
          {
            combined =
              builtins.attrValues self.checks.${system}
              ++ builtins.attrValues self.packages.${system};
          }
          ''
            echo $combined
            touch $out
          ''
      );

      templates = {
        default = self.templates.la-scaffold;
        la-scaffold = {
          path = ./templates/la-scaffold;
          description = "A minimal LA-based scaffold project";
          welcomeText = ''
            Welcome to your new LA-CTL project!

            To enter the Nix environment and start working on it, run `nix develop`. Please make sure to use Nix v2.8 or later.

            Please also see our

            - [Documentation](https://github.com/LovelaceAcademy/cardano-transaction-lib/tree/develop/doc)

            - Generated docs: `npm run dev:docs`

            - [Discord server](https://discord.gg/fWP9eGdfZ8)

            - [StackExchange](https://cardano.stackexchange.com) (:bulb: use the tag `lovelace-academy`)

            If you encounter problems and/or want to report a bug, you reach us on our discord or report to upstream [here](https://github.com/Plutonomicon/cardano-transaction-lib/issues).

            Please search for existing issues beforehand!
          '';
        };
      };

      hydraJobs = perSystem (system:
        self.checks.${system}
        // self.packages.${system}
        // self.devShells.${system}
      );
    };
}
