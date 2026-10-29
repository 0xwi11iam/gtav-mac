# gtav-mac

Native **GTA V** app for Apple Silicon Macs — one script, GTA V.app lands on your Desktop.

Built on [muguet](https://github.com/c22dev/muguet) by **c22dev** (Constantin Clerc), GPL-3.0.
This repo is a macOS-only fork pinned to muguet commit `1a0300d` (verified working build).

## What I changed vs upstream muguet

- **One-script install** — `gta5-installer.sh`: preflight checks, installs missing tools (Rust,
  cmake via Homebrew), waits for you to drop your game files, progress bars, builds, imports,
  drops `GTA V.app` in your home folder and pre-compiles so first launch is instant
- **Rebranded** — app is called **GTA V** (bundle name, window title), bundled app icon
  (drop your own `icon.png` into `~/gta-import` to override)
- **No Xcode needed** — builds with just Command Line Tools (`swiftc` for the launcher);
  the icon is built with `sips` + `iconutil` instead of `actool`
- **macOS only** — stripped the iOS side (`ios/`, `make-ios.sh`) and the upstream
  `build.sh`/`build.command` installers; `make-app.sh` rewritten for this fork
- Self-contained — the installer clones from **this** repo, not upstream

## Prereqs

- Apple Silicon Mac (M1–M4), macOS 14+
- ~40 GB free disk
- Command Line Tools: `xcode-select --install`
- [Homebrew](https://brew.sh) (Rust + cmake get installed for you if missing)

## Your game files — you bring them

**This repo does not host, distribute, or link any Rockstar / GTA game content.**
Bring your own `data/` (~16 GB) and `b/` (with `game.wasm` + `shaders/`) from the web port.
The script waits while you drop them into `~/gta-import`.

## Run

```bash
curl -fsSL https://raw.githubusercontent.com/0xwi11iam/gtav-mac/main/gta5-installer.sh | bash
```

Manual: `git clone` this repo, run `bash gta5-installer.sh`, or build directly with `./make-app.sh`.

Flags: `--force` skips the disk-space checks · `--mirror` forces cargo to fetch crates
from the rsproxy CDN (if crates.io is slow/blocked on your network, the script also
detects and switches automatically).

## Multiplayer

Launcher → "Play with friends" → Host or Join. UDP port 47520 (forward it on the host's
router for internet play). Everyone needs their own build + game files.

## Cleanup after it works

```bash
rm -rf ~/gta-import/game.zip ~/gta-import/data ~/gta-import/b   # ~32 GB back
rm -rf ~/gta-build                                              # build cache
```
