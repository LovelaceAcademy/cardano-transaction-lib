# CTL FAQ

This document lists common problems encountered by CTL users and developers.

**Table of Contents**

- [Bundling-related](#bundling-related)
- [Time-related](#time-related)
- [Ecosystem](#ecosystem)
- [Miscellaneous](#miscellaneous)

## Bundling-related

### Q: `lib.something` is not a function, why?

This is probably because npm is used directly. This is something users have reported when using `npm install` instead of having Nix manage the node dependencies (done automatically with `nix develop`, but if you have `node_modules` present in the working directory it will shadow the ones from the Nix store).

You can prevent `npm` from ever installing to local `node_modules` by enabling the `packageLockOnly` flag in the `shell` argument to `purescriptProject`. When enabled, `npm i` will always act as if the `--package-lock-only` flag has been passed. This is not enabled by default, but we recommend enabling it.

## Time-related

### Q: Time-related functions behave strangely, what's the reason?

Local `cardano-node` lags behind the global network time, so when using time conversion functions (`slotToPosixTime`, `posixTimeToSlot`, etc.) users should be aware that the node sees time differently from the OS. During normal runs, the lag can be somewhere between 0 and 200 seconds.

To do anything time-related, it's best to rely on local node chain tip time, instead of using `Date.now()` as a source of truth. This is often a requirement when using `mustValidateIn`, because the node will reject the transaction if it appears too early.

### Q: Time/slot conversion functions return `Nothing`. Why is that?

Time/slot conversion functions depend on `eraSummaries` [Ogmios local state query](https://ogmios.dev/mini-protocols/local-state-query/), that returns era bounds and slotting parameters details, required for proper slot arithmetic. The most common source of the problem is that Ogmios does not return enough epochs into the future.

### Q: I'm getting `Uncomputable slot arithmetic; transaction's validity bounds go beyond the foreseeable end of the current era: PastHorizon`

Ensure your transaction's validity range does not go over `SafeZone` slots of the current era. The reason for this kind of errors is that time-related estimations are slot-based, and future forks may change slot lengths. So there is only a relatively small time window in the future during which it is known that forks cannot occur.

## Ecosystem

### Q: Why `aeson` and not `argonaut`?

Haskell's `aeson` library encodes long integers as JSON numbers, which leads to numeric truncation on decoder side if JS `Number` is used. Unfortunately, `purescript-argonaut` does not allow to use another type, because the truncation happens during `JSON.parse` call. `purescript-aeson` is our custom solution that bypasses this limitation by storing numbers as strings. It exposes a very similar API.

## Miscellaneous

### Q: Why am I getting `Error: (AtKey "coinsPerUtxoByte" MissingValue)`?

This is because the node hasn't fully synced. The protocol parameter name changed from `coinsPerUtxoWord` to `coinsPerUtxoByte` in Babbage. CTL only supports the latest era, but Ogmios returns different protocol parameters format depending on current era of a local node.

### Q: Why do I get an error from `foreign.js` when running Plutip tests locally?

The most likely reason for this is that spawning the external processes from `Contract.Test.Plutip` fails. Make sure that all of the required services are on your `$PATH` (see more [here](./runtime.md); you can also set `shell.withRuntime = true;` to ensure that these are always added to your shell environment when running `nix develop`). Also, check your logs closely. You might see something like:

```
/home/me/ctl-project/output/Effect.Aff/foreign.js:532
                throw util.fromLeft(step);
                ^

Error: Command failed: initdb /tmp/nix-shell.2AQ4vD/nix-shell.6SMFfq/6s0mchkxl6w9m3m7/postgres/data
initdb: error: invalid locale settings; check LANG and LC_* environment variables
```

The last line is the the most important part. Postgres will fail if your locale is not configured correctly. We _could_ try to do this in the `shellHook` when creating the project `devShell`, but dealing with locales is non-trivial and could cause more issues than it solves. You can find more information online regarding this error and how to potentially solve it, for example [here](https://stackoverflow.com/questions/41956994/initdb-bin-invalid-locale-settings-check-lang-and-lc-environment-variables) and [here](https://askubuntu.com/questions/114759/warning-setlocale-lc-all-cannot-change-locale).

### How can I write my own Nix derivations using the project returned by `purescriptProject`?

If the different derivation builders that `purescriptProject` gives you out-of-the-box (e.g. `runPursTest`, `bundlePursProject`, etc...) are not sufficient, you can access the compiled project (all of the original `src` argument plus the `output` directory that `purs` produces) and the generated `node_modules` using the `compiled` and `nodeModules` attributes, respectively. These can be used to write your own derivations without needing to recompile the entire project (that is, the generated output can be shared between all of your Nix components). For example:

```nix
{
  project = pkgs.purescriptProject { /* snip */ };

  # `purescriptProject` returns a number of specialized builders
  bundle = project.bundlePursProject { /* snip */ };

  # And attributes allowing you to create your own without
  # needing to deal with `spago2nix` or recompiling your
  # project in different components
  specialPackage = pkgs.runCommand "my-special-package"
    {
      NODE_PATH = "${project.nodeModules}/lib/node_modules";
    }
    ''
      cp -r ${project.compiled}/* .
      # Do more stuff ...
    '';
}

```
