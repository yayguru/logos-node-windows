# Contributing to logos-node-windows

Thanks for helping. Keep changes small and easy to review. Bugs and ideas go to
[issues](https://github.com/yayguru/logos-node-windows/issues/new/choose); security problems are reported privately
(see [SECURITY.md](SECURITY.md)).

- **Panel (`app/panel.ps1`)** must run on stock Windows PowerShell 5.1 (Windows 10/11) without admin rights or extra modules.
  Before sending a change, check it parses: `[System.Management.Automation.Language.Parser]::ParseFile('app/panel.ps1',[ref]$null,[ref]$e); $e.Count` must be `0`.
- Keep the file ASCII-only (PowerShell 5.1 reads BOM-less files as ANSI).
- Never log, print or upload keys, seeds, `data\keystore.yaml` or `data\user_config.yaml`. The node's REST API stays on `127.0.0.1`.
- Do not widen the update path allowlist or add network calls without discussing it in an issue first.
- Test on a throwaway data folder, not on a node that holds funds you care about.
- Node source changes belong upstream in [logos-blockchain](https://github.com/logos-blockchain/logos-blockchain); this unofficial repo only carries
  the minimal Windows build patch.
- Panel changes: describe how you tested them (menu keys or `--` options used, Windows version) in the pull request.
- Build script changes: say which MSYS2/Rust versions you used; see [build/BUILDING.md](build/BUILDING.md).
- Be respectful and constructive in issues and reviews.
- By contributing you agree your contribution is licensed under the MIT licence of this repository (lxpost: MIT OR Apache-2.0).
