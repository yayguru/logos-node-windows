Logos testnet node + miner for Windows (native, no WSL) - blockchain node 0.3.4 (build 8)

1. Unzip anywhere (e.g. C:\LogosMiner).
2. Double-click LogosMiner.bat.
3. Choose:  1 = full node (opens P2P port in Windows Firewall, optional public address/domain)
            2 = mine only (outbound-only node, nothing opened)
   4 = pick how many CPU threads to mine with (asks to restart the node to apply). Default 'auto' = half of your CPU threads.
   R = restart the node (apply a new thread count, or repair a stuck start).
On first start a fresh node identity + keystore is created in .\data (back up data\keystore.yaml, never share it).
A brand-new node must sync and then pass a ~1 hour bootstrap period; mining then starts by itself (menu 3 shows progress and a countdown). A node with existing data is usually mining within a minute or two.
Mining speed depends on CPU threads, not on RAM (32 GB RAM does not add threads). 'Threads 4 of 8' means 4 of your 8 CPU threads mine.
If a slow PC makes the node's mining service fail to start, the panel notices and restarts the node automatically (max 3 times / 6 h); menu R does it by hand.
Menu 9 shows the last lines of data\node.log (times are UTC). Manual claim (C) is optional: the node claims its winning tickets by itself (auto-claim has no balance limit; the panel raises the node default 2,000,000,000 to the maximum at every start).
Settings: logos-miner.ini (threads, mode, api address, p2p port, public address, bootstrap peers, optional claim key).

First-run prompts you may see:
- SmartScreen "Windows protected your PC": the exe is a self-built, unsigned binary. Click "More info" -> "Run anyway" (only if you got this zip from a source you trust; compare the zip's SHA-256 with the SHA256SUMS published next to it).
- Windows Firewall "allow access" dialog when the node starts: allow on Private networks for full-node mode; mine-only works even if you click Cancel (outbound only).
- Full-node mode asks for Administrator (UAC) once to add the P2P firewall rule. Mine-only mode removes that rule again.
Security notes: the REST API listens on 127.0.0.1 only and is locked to loopback CORS; data\ (keystore) is restricted to your user, SYSTEM and Administrators.
No Administrator rights and no Developer Mode needed for mine-only mode (the node's log-file symlink problem is handled by the panel).
If the node fails to start the panel stops waiting at once and shows the node's last log lines with a plain explanation.

Wallet + inscriptions (menu items W and I):
- W = Wallet balance: shows this node's wallet key (full, public) and its balance in base units (a key with no coins yet shows 0).
- I = Inscribe: write text, an image (JPEG/PNG/GIF/WebP) or any other file permanently onto the Logos chain.
  It explains how it works, shows the maximum size (1,835,008 bytes = 1.75 MiB incl. a small header), checks your file, shows the exact byte count
  and the exact fee (base units, computed from the bytes and the live network prices), your balance before/after, and asks you to type YES.
  Nothing is sent before that. Inscriptions are PUBLIC and PERMANENT and the fee is not refunded. The tx hash and an explorer link (logos.ulti.mom) are shown in full.
  Tip: shrink images first (Paint/Photos resize + JPEG 70-80%, or WebP) - cost grows with size. Your inscription signing key lives in data\inscribe_key.json (back it up with keystore.yaml).
  Test without sending anything:  LogosMiner.bat --inscribe --dry-run     (balance only:  LogosMiner.bat --balance)

Send + Receive (new in v7, menus S and A):
- S = Send coins to any Logos key (64 hex characters). Shows balance and the fee (calculated from your coin list; the node confirms the exact figure when you type SEND; includes a 12% safety margin), the coins used, the change returned to you, and balance before/after.
  Nothing is sent until you type SEND. Transfers are FINAL. One transfer can use at most 32 coins; to send more, first send to your own key to merge coins.
  The preview reserves nothing; after you type SEND (or cancel at the second confirmation) the node keeps the chosen coins reserved for ~10 minutes. Only coins can be sent (inscriptions cannot be sent one by one).
  Test without sending anything:  LogosMiner.bat --send --dry-run
- A = Receive: shows your PUBLIC wallet key (copied to the clipboard), balance, recent incoming transfers (from the explorer) and your last sends. Also: LogosMiner.bat --receive
- Sends are logged in data\transfers.log (destination, amount, fee, tx hash - never keys).

Mining on/off (v6): menu 6 = start mining right now, menu 5 = stop mining (node keeps running). Both really talk to the node and tell you whether it confirmed.
The status line 'Mining' comes from the node itself (/pow/status), and from the node log while the node is too busy to answer. A hidden helper switches mining on once the chain is Online; it never restarts a healthy node.
Update (menu U, experimental): checks a signed manifest (logos.ulti.mom/miner/manifest.json), downloads only the files that changed, verifies their SHA-256 and the release signature,
backs up the old files (update\backup-*), swaps them in, restarts the node and checks it comes back; if not, the old files are put back automatically.
data\ (keys, chain), logos-miner.ini are never touched. Menu U > 2 rolls back by hand. Command line: LogosMiner.bat --update-check | --update | --rollback.
Node 0.3.4 (build 8): on its first start the node converts data\user_config.yaml to the 0.3.4 format and keeps the old file as
data\user_config.yaml.0.3.2.bak. Before every start the panel now asks the node to check the config (--check-config) and stops with a
plain message if it is not valid. A rollback made by this panel (menu U > 2) puts the matching config back automatically.
If an OLDER panel (build 6/7) rolled back from 0.3.4 and the node then does not start: in data\ rename user_config.yaml to
user_config.yaml.034 and user_config.yaml.0.3.2.bak to user_config.yaml, then start again.

What is inside / where it comes from:
- bin\logos-blockchain-node.exe: there is no official Windows release of the node, so this is a community build of the official
  logos-blockchain source at tag 0.3.4 (commit f7ab0323), built with MSYS2 MinGW-w64 (x86_64-pc-windows-gnu). It is NOT an official
  Logos binary and is not code-signed. One small local patch is needed on Windows, in rust-rapidsnark: c_ulong cast (32-bit long
  on Windows) and trimming the NUL padding of the proof string (without it the node panicked when going Online). The earlier
  startup-wait patch is no longer needed (0.3.4 has no such timeout). No other node source changes;
  rapidsnark + GMP were built with the circuits repo's Windows build recipe.
- bin\lxpost.exe: small helper used by Inscribe and Send to build/sign transactions locally (keys never leave this PC).
- bin\libgcc_s_seh-1.dll, libstdc++-6.dll, libwinpthread-1.dll: unmodified MSYS2 runtime DLLs (byte-identical to MSYS2 packages
  libgcc/libstdc++ 16.2.0-6 and libwinpthread 14.0.0.r426-2).
- Licences: see the LICENSES folder and THIRD-PARTY-NOTICES.txt.
Network contacts: the node talks to the Logos testnet peers. The panel itself only contacts the community explorer
logos.ulti.mom (Receive/Send look-ups and links) and, only when you use menu U, the update manifest. Nothing is sent automatically.
