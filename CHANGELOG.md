# Changelog

Unofficial Windows build of the Logos blockchain node. Build numbers are this project's own; the node version is upstream's.
Builds 1 to 7 were released before this repository was public (build 6 was the first signed-update release).
Times are approximate. Builds 1 to 7 bundle node 0.3.2.

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
