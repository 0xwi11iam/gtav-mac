#!/bin/bash
# gta5-installer.sh — builds a native "GTA V" app (muguet engine) on your Mac.
# You supply your own game data (data/ + b/). Nothing copyrighted is downloaded.
#
# Usage:  bash gta5-installer.sh
#   or:   curl -fsSL <script url> | bash
set -euo pipefail

FORCE=0
MIRROR=0
for a in "$@"; do
  case "$a" in
    --force) FORCE=1 ;;
    --mirror) MIRROR=1 ;;
  esac
done

# ── config ────────────────────────────────────────────────────────────────────
INSTALL_URL="https://raw.githubusercontent.com/0xwi11iam/gtav-mac/main/gta5-installer.sh"
MUGUET_REPO="https://github.com/0xwi11iam/gtav-mac"
BUILD_ROOT="$HOME/gta-build"       # clone + rust build lives here
DATA_DIR="$HOME/gta-import"        # <- you drop data/ and b/ here
APP_DEST="$HOME/Desktop/GTA V.app"
FREE_GB_NEEDED=40

# ── colors ────────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  B=$(printf '\033[1m'); DIM=$(printf '\033[2m')
  RED=$(printf '\033[31m'); GREEN=$(printf '\033[32m'); YEL=$(printf '\033[33m')
  CYAN=$(printf '\033[36m'); GRAY=$(printf '\033[90m'); R=$(printf '\033[0m')
else
  B=""; DIM=""; RED=""; GREEN=""; YEL=""; CYAN=""; GRAY=""; R=""
fi

step_n=0; step_t=12
step() { step_n=$((step_n+1)); printf '\n%s%s──[ %sStep %d/%d%s ]── %s%s%s ──%s\n' \
  "$B" "$CYAN" "$R" "$step_n" "$step_t" "$B" "$CYAN" "$1" "$R"; }
ok()    { printf '  %s✔ %s%s%s\n' "$GREEN" "$R" "$1" "${2:+ $GRAY$2$R}"; }
warn()  { printf '  %s! %s%s%s\n' "$YEL" "$R" "$1" "${2:+ $GRAY$2$R}"; }
fail()  { printf '  %s✘ %s%s\n' "$RED" "$R" "$1" >&2; exit 1; }
note()  { printf '  %s%s%s\n' "$GRAY" "$1" "$R"; }

# spinner <pid> <label>   — animates until pid exits
spinner() {
  local pid=$1 label=$2 i=0
  local chars="|/-\\"
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r  %s%s%s %s   %s' "$CYAN" "${chars:i%4:1}" "$R" "$label" "$DIM   $R"
    i=$((i+1)); sleep 0.15
  done
  printf '\r%*s\r' $(( ${#label} + 12 )) ''
}

bar() { # bar <pct> <label>
  local pct=$1 label=$2 width=28 filled
  [ "$pct" -gt 100 ] && pct=100
  filled=$(( width * pct / 100 ))
  printf '\r  %s%*s%s' "$GREEN" "$filled" "" "$R" | tr ' ' '#'
  printf '%s%*s%s' "$GRAY" "$(( width - filled ))" "" "$R" | tr ' ' '-'
  printf ' %s%3d%%%s  %s%*s' "$B" "$pct" "$R" "$label" $(( 34 - ${#label} < 0 ? 0 : 34 - ${#label} )) ''
}

# ── re-exec when piped from curl ─────────────────────────────────────────────
if [ "${BASH_SOURCE[0]:-}" != "$0" ]; then
  # running as `curl ... | bash` — prompts would eat our own script; re-exec from a file
  if [ -n "${INSTALL_URL:-}" ]; then
    tmp=$(mktemp /tmp/gta5-installer.XXXXXX)
    curl -fsSL "$INSTALL_URL" -o "$tmp"
    if ( : < /dev/tty ) 2>/dev/null; then
      exec bash "$tmp" "$@" < /dev/tty
    else
      exec bash "$tmp" "$@"
    fi
  fi
  printf '%s\n' "Piping this script into bash eats the interactive prompts." \
    "Download it first:  curl -fsSL -o gta5-installer.sh <url>  then  bash gta5-installer.sh" >&2
  exit 1
fi

# ═══════════════════════════════════════════════════════════════ preflight ═══

step "Checking this Mac"
[ "$(uname -s)" = "Darwin" ] || fail "macOS only."
[ "$(uname -m)" = "arm64" ] || fail "Apple Silicon (M1/M2/M3/M4) required — this is $(uname -m)."
os_major=$(sw_vers -productVersion | cut -d. -f1)
[ "${os_major:-0}" -ge 14 ] 2>/dev/null || fail "macOS 14 (Sonoma) or later required — you have $(sw_vers -productVersion). Sequoia 15 recommended."
ok "macOS $(sw_vers -productVersion) on $(uname -m)$([ "${os_major:-0}" -ge 15 ] && echo ' — Sequoia or newer ✓')"

free_gb=$(df -g "$HOME" | awk 'NR==2 {print $4}')
if [ "${free_gb:-0}" -lt 20 ]; then
  if [ "$FORCE" = 1 ]; then
    warn "--force: running with only ${free_gb} GB free — this will likely fail mid-install"
  else
    fail "need at least 20 GB free to attempt an install — you have ${free_gb} GB. (rerun with --force to override)"
  fi
fi
if [ "${free_gb:-0}" -lt "$FREE_GB_NEEDED" ]; then
  warn "only ${free_gb} GB free (recommended ${FREE_GB_NEEDED}) — the real check runs once your data is in place"
fi
ok "${free_gb} GB free"

if ! xcode-select -p >/dev/null 2>&1; then
  warn "Command Line Tools missing — launching Apple's installer now"
  xcode-select --install 2>/dev/null || true
  printf '    %sClick Install in the window that opened; when it finishes, run this script again.%s\n' "$B" "$R"
  exit 1
fi
ok "Command Line Tools: $(xcode-select -p)"
for t in git zip unzip swiftc sips iconutil; do
  command -v "$t" >/dev/null || fail "$t missing — run: xcode-select --install"
done

# ═══════════════════════════════════════════════════════════ tools (brew) ════
step "Checking tools (Homebrew, Rust, cmake)"
if ! command -v brew >/dev/null; then
  warn "Homebrew missing — installing now"
  printf '    %sIt will ask for your Mac password and to press Return — that is normal, type away.%s\n' "$DIM" "$R"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || true)"
fi
if [ "$(uname -m)" = "arm64" ] && [ -x /opt/homebrew/bin/brew ]; then
  export PATH="/opt/homebrew/bin:$PATH"
fi
ok "brew $(brew --version | head -1 | awk '{print $2}')"

if ! command -v cargo >/dev/null; then
  brew install rust >/dev/null 2>&1 &
  spinner $! "installing Rust via Homebrew (a few minutes)"
fi
command -v cargo >/dev/null || fail "Rust install failed — try: brew install rust"
ok "$(rustc --version | head -1)"

if ! command -v cmake >/dev/null; then
  brew install cmake >/dev/null 2>&1 &
  spinner $! "installing cmake (needed for the audio codec)"
fi
command -v cmake >/dev/null || fail "cmake install failed — try: brew install cmake"
ok "cmake $(cmake --version | head -1 | awk '{print $3}')"

# ═══════════════════════════════════════════════════════════ clone muguet ════
step "Fetching the engine from your repo"
mkdir -p "$BUILD_ROOT"
if [ ! -d "$BUILD_ROOT/muguet/.git" ]; then
  git clone -q "$MUGUET_REPO" "$BUILD_ROOT/muguet" &
  spinner $! "cloning $MUGUET_REPO"
else
  note "existing clone at $BUILD_ROOT/muguet — updating"
fi
cd "$BUILD_ROOT/muguet"
git fetch -q origin 2>/dev/null || true
git reset -q --hard origin/main 2>/dev/null || warn "could not sync to origin/main" "building what is here"
ok "engine source ready $(git rev-parse --short HEAD 2>/dev/null || echo '?')"

# brand the launcher window title (best-effort, non-fatal)
sed -i '' 's/WindowGroup("Muguet")/WindowGroup("GTA V")/' launcher/Launcher.swift 2>/dev/null || true
ok 'branded: window title → "GTA V"'

# ═════════════════════════════════════════════════════ write our build script ═
step "Writing the “GTA V” build script"
cat > make-app.sh <<'MAKEAPP'
#!/bin/sh
# GTA V (muguet) — macOS bundle assembly
set -eu
cd "$(dirname "$0")"
APP="$PWD/build/GTA V.app"
cargo build --release
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp target/release/muguet target/release/muguet-server "$APP/Contents/MacOS/"
if [ -x "$APP/Contents/MacOS/Launcher" ] && [ "$APP/Contents/MacOS/Launcher" -nt launcher/Launcher.swift ]; then :; else
  swiftc -O -parse-as-library -target arm64-apple-macos14 launcher/Launcher.swift -o "$APP/Contents/MacOS/Launcher"
fi
cp assets/*.mp3 "$APP/Contents/Resources/" 2>/dev/null || true
[ -f build/AppIcon.icns ] && cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns" || true
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>GTA V</string>
  <key>CFBundleDisplayName</key><string>GTA V</string>
  <key>CFBundleIdentifier</key><string>ch.cclerc.muguet</string>
  <key>CFBundleExecutable</key><string>Launcher</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>GCSupportsGameMode</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>Multiplayer connects to a game server on your local network.</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><false/>
  <key>MuguetEmbeddedCode</key><false/>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
echo "built: $APP ($(du -sh "$APP" | cut -f1))"
MAKEAPP
chmod +x make-app.sh
ok "make-app.sh replaced with GTA V branding (no Xcode needed)"

# ══════════════════════════════════════════════════════════════════ icon ════
step "Building the app icon"
mkdir -p "$DATA_DIR" build
ICON_SRC=""
for f in icon.png icon.jpg icon.jpeg gta.jpeg gta.png; do
  [ -f "$DATA_DIR/$f" ] && ICON_SRC="$DATA_DIR/$f" && break
done
if [ -n "$ICON_SRC" ]; then
  rm -f build/AppIcon.icns
  ok "using your icon: $ICON_SRC"
elif [ -f assets/AppIcon.icns ]; then
  rm -f build/AppIcon.icns
  cp assets/AppIcon.icns build/AppIcon.icns
  ok "using the bundled AppIcon.icns"
fi
if [ ! -f build/AppIcon.icns ] && [ -z "$ICON_SRC" ]; then
  printf '%s' "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" | base64 -D > build/vicon.png 2>/dev/null || \
  printf '%s' "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" | base64 -d > build/vicon.png
  ICON_SRC="$PWD/build/vicon.png"
  note "using built-in V icon (drop icon.png into $DATA_DIR to use your own)"
fi
if [ -n "$ICON_SRC" ]; then
ICONSET=build/iconset; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -s format png -z $s $s "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -s format png -z $((s*2)) $((s*2)) "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
if iconutil -c icns "$ICONSET" -o build/AppIcon.icns >/dev/null 2>&1; then
  ok "AppIcon.icns (iconutil)"
else
  python3 - <<'PYICON' && ok "AppIcon.icns (python fallback)" || warn "icon packing failed" "app works, just no custom icon"
import struct
from pathlib import Path
src = Path("build/iconset")
entries = [(b"icp4","icon_16x16.png"),(b"ic11","icon_16x16@2x.png"),(b"ic12","icon_32x32@2x.png"),
           (b"ic07","icon_128x128.png"),(b"ic08","icon_256x256.png"),(b"ic13","icon_128x128@2x.png"),
           (b"ic09","icon_512x512.png"),(b"ic14","icon_256x256@2x.png"),(b"ic10","icon_512x512@2x.png")]
body = b""
for code, name in entries:
    data = (src / name).read_bytes()
    body += code + struct.pack(">I", len(data) + 8) + data
Path("build/AppIcon.icns").write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)
PYICON
fi
rm -rf "$ICONSET"
fi
[ -f build/AppIcon.icns ] && ok "icon ready: $(du -h build/AppIcon.icns | cut -f1)" || warn "no icon" "app still works"

# ═════════════════════════════════════════════════════ wait for game data ═══
step "Your game data — self-provided"
printf '  Drop these into %s%s%s :\n' "$B" "$DATA_DIR" "$R"
printf '    %sdata/%s   (the game data folder, ~16 GB)\n' "$CYAN" "$R"
printf '    %sb/%s      (the build folder with game.wasm + shaders)\n' "$CYAN" "$R"
printf '  %s(optional)%s icon.png — becomes the app icon\n' "$DIM" "$R"
printf '\n'
while :; do
  if [ -f "$DATA_DIR/data/manifest.json" ] && ls "$DATA_DIR"/b/*/game.wasm >/dev/null 2>&1; then
    ok "found data/manifest.json + b/*/game.wasm"
    break
  fi
  printf '  %s… waiting — press %sEnter%s to re-check (Ctrl+C to quit)%s\r' "$YEL" "$B" "$R" "$R"
  read -r _ || exit 1
  printf '\r%*s\r' 70 ''
done
payload_b=$(find "$DATA_DIR/data" "$DATA_DIR"/b -type f -print0 2>/dev/null | xargs -0 stat -f%z 2>/dev/null | awk '{s+=$1} END {print s+0}')
payload_gb=$(( (payload_b + 1073741823) / 1073741824 ))
need_gb=$(( payload_gb * 2 + 6 ))
free_gb2=$(df -g "$HOME" | awk 'NR==2 {print $4}')
if [ "${free_gb2:-0}" -lt "$need_gb" ]; then
  if [ "$FORCE" = 1 ]; then
    warn "--force: need ${need_gb} GB free, have ${free_gb2} GB — if the disk fills mid-import, rerun; it resumes clean"
  else
    fail "your data is ${payload_gb} GB — need ${need_gb} GB free for zip + import copy + build (have ${free_gb2} GB). rerun with --force to override"
  fi
fi
ok "payload ${payload_gb} GB · ${free_gb2} GB free · ${need_gb} GB needed"

# ══════════════════════════════════════════════════════════ staging zip ══════
step "Packing your data (store-mode zip, ~16 GB — minutes)"
ZIP="$DATA_DIR/game.zip"
src_bytes=$(du -sk "$DATA_DIR/data" "$DATA_DIR"/b/*/ 2>/dev/null | awk '{s+=$1} END {print s+0}')
src_bytes=$(( src_bytes * 1024 ))
rm -f "$ZIP"
( cd "$DATA_DIR" && zip -0 -r -q game.zip data b -x '*.DS_Store' ) &
zpid=$!
while kill -0 "$zpid" 2>/dev/null; do
  sleep 2
  zbytes=$(stat -f%z "$ZIP" 2>/dev/null || echo 0)
  pct=$(( zbytes * 100 / (src_bytes == 0 ? 1 : src_bytes) ))
  bar "${pct:-0}" "packing $(awk -v a="${zbytes:-0}" -v b="$src_bytes" 'BEGIN{printf "%.1f/%.1f GiB", a/1073741824, b/1073741824}')"
done
wait "$zpid" || fail "zip failed"
bar 100 "packing done"
printf '\n'; ok "game.zip ready ($(du -sh "$ZIP" | cut -f1))"

# ═══════════════════════════════════════════════════════ rust compile ════════
step "Compiling the engine (Rust release build, ~2–5 min)"
if [ "$MIRROR" = 1 ]; then
  warn "--mirror: forcing cargo to the rsproxy CDN"
  grep -q 'source.rsproxy' .cargo/config.toml 2>/dev/null || printf '\n[source.crates-io]\nreplace-with = "rsproxy"\n[source.rsproxy]\nregistry = "sparse+https://rsproxy.cn/index/"\n' >> .cargo/config.toml
elif ! curl -fsS -m 10 -o /dev/null "https://static.crates.io/crates/anyhow/1.0.104/anyhow-1.0.104.crate" 2>/dev/null; then
  warn "static.crates.io unreachable — switching cargo to the rsproxy CDN (--mirror forces this)"
  grep -q 'source.rsproxy' .cargo/config.toml 2>/dev/null || printf '\n[source.crates-io]\nreplace-with = "rsproxy"\n[source.rsproxy]\nregistry = "sparse+https://rsproxy.cn/index/"\n' >> .cargo/config.toml
fi
cargo fetch --locked >/dev/null 2>&1 || cargo fetch >/dev/null 2>&1 || true
( cargo build --release > build/build.log 2>&1 ) &
bpid=$!
spin_label="compiling wasmtime + wgpu (release)"
while kill -0 "$bpid" 2>/dev/null; do
  done_crates=$(ls target/release/build 2>/dev/null | grep -c '^.*' || true)
  sleep 1
  kill -0 "$bpid" 2>/dev/null && printf '\r  %s…%s %s (%s crates staged)%s   ' "$CYAN" "$R" "$spin_label" "${done_crates:-0}" "$DIM"
done
printf '\r%*s\r' 80 ''
if ! wait "$bpid"; then tail -25 build/build.log || true; fail "Rust build failed — log: $PWD/build/build.log"; fi
ok "engine compiled"

step "Assembling the GTA V app"
./make-app.sh | tail -1
ok "bundle codesigned (ad-hoc)"

# ═══════════════════════════════════════════════════════════ import data ════
step "Importing your game data (~16 GB copy)"
GAME_HOME="$HOME/Library/Application Support/Muguet"
import_log="$BUILD_ROOT/import.log"; import_rc="$BUILD_ROOT/import.rc"
rm -f "$import_log" "$import_rc"
( "$BUILD_ROOT/muguet/target/release/muguet" --import "$ZIP" > "$import_log" 2>&1; echo $? > "$import_rc" ) &
ipid=$!
last=0
while kill -0 "$ipid" 2>/dev/null; do
  p=$( { grep '^progress ' "$import_log" 2>/dev/null || true; } | tail -1 | awk '{print $2, $3}')
  if [ -n "$p" ]; then
    set -- $p
    if [ "${2:-0}" -gt 0 ] 2>/dev/null; then
      pct=$(( $1 * 100 / $2 ))
      [ "$pct" -ne "$last" ] && bar "$pct" "importing" && last=$pct
    fi
  fi
  sleep 1
done
if ! grep -q '^progress ' "$import_log" || [ "$(cat "$import_rc" 2>/dev/null)" != "0" ]; then
  tail -5 "$import_log" 2>/dev/null || true
  fail "import failed"
fi
bar 100 "import complete"; printf '\n'
[ -f "$GAME_HOME/game/data/manifest.json" ] && ok "game data installed" || fail "game data missing after import"

# ═════════════════════════════════════════════════════════ finish + done ════
step "Installing the app"
rm -rf "$APP_DEST"
ditto "build/GTA V.app" "$APP_DEST"
ok "$APP_DEST ($(du -sh "$APP_DEST" | cut -f1))"
touch "$APP_DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP_DEST" >/dev/null 2>&1 || true

step "One-time game compile (optional prewarm)"
if "$BUILD_ROOT/muguet/target/release/muguet" --compile > "$BUILD_ROOT/compile.log" 2>&1; then
  ok "native code cached — first launch is instant"
else
  warn "prewarm failed" "the app will compile on first Play instead"
fi

printf '\n%s%s✔ All done.%s\n\n' "$B$GREEN" "$B" "$R"
printf '  %sGTA V.app%s is on your Desktop. Double-click, press %sPlay%s.\n' "$B" "$R" "$B" "$R"
printf '  In game: %sCmd+F%s fullscreen · %sCmd+Q%s quit · mouse release with %sCmd+key%s\n' "$B" "$R" "$B" "$R" "$B" "$R"
printf '\n  %sMultiplayer:%s launcher → “Play with friends” → Host or Join (UDP 47520).\n' "$B" "$R"
printf '\n  %sCleanup when you are happy it works:%s\n' "$DIM" "$R"
printf '    rm -rf %s/game.zip   %s# ~16 GB back%s\n' "$DATA_DIR" "$DIM" "$R"
printf '    rm -rf %s/data %s/b  %s# another ~16 GB%s\n' "$DATA_DIR" "$DATA_DIR" "$DIM" "$R"
printf '    (keep ~/gta-build if you ever want to rebuild; delete to reclaim ~4 GB)\n'
printf '\n'
