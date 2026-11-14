# Changelog

Unofficial Windows build of the Logos blockchain node. Build numbers are this project's own; the node version is upstream's.
Builds 1 to 7 were released before this repository was public (build 6 was the first signed-update release).
Times are approximate. Builds 1 to 7 bundle node 0.3.2.

## Build 12 / module v0.3.4-windows.2 (2026-11-14), node 0.3.4 + build 11 + voucher path sharing
Fixes the memory leak where the node's RSS grew by hundreds of MB to several GB over a few hours (same
behaviour on Linux and Windows). The wallet kept one `WalletState` per applied block and, on every new
block, rebuilt a unique map of tracked voucher Merkle paths (cloning every path). Until LIB prune (and
during IBD) those copies accumulated.
- **Fix.** `wallet` / `mmr`: share unchanged voucher paths between per-block states (`push_with_lazy_paths`).
  A path is updated only when the new voucher settles it. This is the mem/0.3.4-instrumentation work applied
  on top of build 11, plus a regression test.
- **Evidence (debug unit test, 32 tracked vouchers, 3000 extra blocks, 3033 states kept).**
  Build 11 / current: anonymous RSS +114532 kB. After the fix: +1276 kB (~90× less, nearly flat).
  `cargo test -p logos-blockchain-wallet -p logos-blockchain-mmr`: 20 + 23 passed.
- Source: `build/patches/node-0.3.4-v12-memfix.patch`, applied after the v11 patch. Shipped as the node
  library inside yayguru/logos-blockchain-module prerelease v0.3.4-windows.2. No standalone Windows zip
  in this repository.

## Build 11 (2026-11-12), node 0.3.4 + fixes
Fixes PoW claims that stop settling after this node proposes its own block ("claims stop after my block"). The node had to
be restarted to recover; it no longer does.
- **Cause.** Blend sends this node's locally made messages from two queues, block proposals and transactions (PoW claims are
  the only transactions it carries). The head proposal was always served first (`services/blend/src/pending.rs`,
  `next_local_message`), and encapsulating it awaits a leadership proof (`edge/current_epoch.rs` and `core/mod.rs`,
  `encapsulate_next_local_message`). That proof comes from the PoL scan for winning slots; when it is late the await never
  ends, and when it is not available (`ProofNotAvailable`, mapped to `Retry`) the send branch is disabled. Either way no claim
  behind the proposal was ever sent; they piled up (Blend pending over 1,000) and expired after 100 slots. The proposal queue
  only cleared at the next epoch or a restart.
- **Fix in Blend.** A proposal keeps priority for 2 s after it is queued; after that it is still tried first on every turn,
  but only with proofs that are already there, and the next claim goes meanwhile. The budget is counted from queue time,
  so other events that wake the loop (new claims, status requests) cannot keep resetting it. A proposal older than 60 s and
  a transaction older than 90 s (its claim window has closed) are dropped instead of blocking the queue.
- **Fix in PoW.** A claim that is still unsettled 45 slots after it was first seen pending is moved back to "ready" and claimed
  again in a new transaction while its window is open. Tickets whose nullifier the ledger already records are retired before
  a claim is built, so a ticket is never paid twice and a late duplicate never spoils a new claim transaction.
- **Tests.** New tests run a stuck own proposal with 5 claims behind it (proof never comes; quota exhausted; and the loop
  being woken every 500 ms). All three fail on build 10 code ("claim 0 of 5 never left") and pass on build 11. Blend service
  lib tests: 114 passed, 1 ignored (pre-existing). PoW service lib tests: 54 passed.
- **Not yet verified.** That claims keep settling across a real own block proposal on the testnet. Why the leadership proof
  is late (most likely the PoL scan running slower than the chain on nodes with many notes) is not fixed here; that proposal
  may still go out late or be dropped after 60 s. Time limits are in seconds and assume about 1 s per slot.
- No restart-based watchdog: the panel is unchanged apart from the build number.

## Build 10 (2026-11-07), node 0.3.4 + upstream PR 3986 backport
- Blend winning-slot pre-poll (upstream PR 3986, commit `9739b5fc`) backported onto tag `0.3.4`. Did not fix the claim stall
  after an own block proposal (see build 11).

## Build 9 (2026-10-31), node 0.3.4 (unchanged)
- Renamed from "LogosMiner" to **Logos Node for Windows**: `LogosNode.bat`, `logos-node.ini`, zip `LogosNode-win64-<version>.zip`,
  and the panel's product name and texts.
- Migration for installs of builds 6 to 8: the panel adds `LogosNode.bat` next to `LogosMiner.bat` and keeps using an existing
  `logos-miner.ini`; it never renames or edits the old launcher, the settings or `data\`. The status screen shows the settings
  file in use. If both settings files exist, the old one wins unless the new one was edited. New option `--settings-file`.
- The update manifest keeps `"app": "LogosMiner"` and the same URL so build 6 to 8 panels keep updating; the panel accepts
  `LogosMiner` and `LogosNode`.
- Fix: after menu U (and after starting the node from the menu) "Press Enter" could do nothing. Likely cause: the hidden helper the
  panel starts could briefly get a console window and keep the keyboard focus while hidden. Helpers are now created hidden
  (Win32_ProcessStartup ShowWindow = 0) and the panel takes the focus back. After a successful update the panel now opens the
  new panel in a new window by itself. Panels of builds 6 to 8 still have the old behaviour while they install this update:
  click once inside the window, or just close it.

## Repository updates (no new build)
- 2026-10-31: README picture and social preview image (mock-ups with example values), ASCII banner, a pinned
  disclaimer, issue forms, a pull request checklist, supported versions in SECURITY.md.

## Build 8 (2026-10-31), node 0.3.4
- Node `logos-blockchain-node` 0.3.4 (upstream tag `0.3.4`, commit `f7ab0323`), same one-line Windows patch as before.
- An existing 0.3.2 `data\user_config.yaml` is converted on first start; the original is kept as `user_config.yaml.0.3.2.bak`.
- The panel runs `--check-config` before every start; update rollback also restores the matching config.
- Includes the Send (S) and Receive (A) menus developed as the build 7 candidate.
- First release published on GitHub, with sources, build scripts and third-party licence texts.

## Build 7 (2026-10-16 to 10-19), candidate, not released on its own
- Send (S) and Receive (A): transfers built and signed locally by `lxpost.exe`, fee shown, typed confirmation, `--dry-run`.
- Security review of the updater (signature checked before parsing, no downgrade or replay, https/file only, path allowlist).

## Build 6 (2026-10-15)
- Mining really starts: a helper re-arms `PUT /pow/mining/start` once the node is Online, and respects a manual pause.
- Mining state comes from `/pow/status`, with a fallback to the node log when the node answers 408.
- **Update menu (U)**: RSA-3072 signed manifest, per-file SHA-256, backup and automatic rollback.

## Build 5 (2026-10-15)
- Auto-claim threshold raised from 2,000,000,000 to the maximum, so mining and auto-claim do not stop at that balance.

## Build 4 (2026-10-15)
- `threads=auto`, a status screen with a bootstrap countdown, restart menu (R), auto-heal restart (at most 3 in 6 h), and a better log view.

## Build 3 (2026-10-15)
- Wallet balance (W) and Inscribe (I) menus: text, images and files.
- Works without admin rights or Developer Mode: the node's file logger, which needs symlinks, is disabled and logs go to `data\node.log`.

## Build 2 (2026-10-15)
- Claim rewards (C) fixed: retries and a progress spinner while the node's PoW endpoints are slow (HTTP 408).

## Build 1 (2026-10-14)
- First native Windows build of the node 0.3.2 with MinGW-w64: rapidsnark/GMP for MinGW, link fixes for the official
  circuits libraries, a `c_ulong` cast and NUL-trim in rust-rapidsnark.
- Panel: full node or mine-only, firewall rules, CORS pinned to loopback, ACL on `data\`.
