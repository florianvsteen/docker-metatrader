#!/bin/bash
# ================================================================
# first-run.sh
# Called once on first container start.
# Creates a Bottles environment and silently installs MT5.
# ================================================================
set -euo pipefail

BOTTLE_NAME="${1:-metatrader5}"
MT5_EXE="${2:-C:\\Program Files\\MetaTrader 5\\terminal64.exe}"
INSTALLER="${3:-/home/trader/mt5setup.exe}"

BOTTLES_CLI="flatpak run --command=bottles-cli com.usebottles.bottles"

log() { echo "[SETUP $(date '+%H:%M:%S')] $*"; }

# ── Create the Bottle ─────────────────────────────────────────
log "Creating bottle '$BOTTLE_NAME' (Windows 10, win64)..."
log "This will take 5–10 minutes on first run..."

$BOTTLES_CLI new \
    --bottle-name "$BOTTLE_NAME" \
    --environment custom \
    --arch win64

log "✓ Bottle created."

# ── Install runtime dependencies ─────────────────────────────
# vcredist2019: Visual C++ redistributable (MT5 requires this)
# dotnet48:     .NET 4.8 (needed by some EAs and the terminal itself)
log "Installing Windows runtime dependencies..."

for dep in vcredist2019 dotnet48; do
    log "  → $dep ..."
    $BOTTLES_CLI install-dep \
        --bottle-name "$BOTTLE_NAME" \
        --dep "$dep" 2>&1 \
    && log "  ✓ $dep installed." \
    || log "  ⚠ $dep failed (may already be present, continuing)."
done

# ── Silent MT5 install ────────────────────────────────────────
log "Running MT5 installer silently..."
log "(Installer: $INSTALLER)"

# /S = silent, /D = install directory
$BOTTLES_CLI run \
    --bottle-name "$BOTTLE_NAME" \
    --exec "$INSTALLER" \
    -- /S

log "Waiting for MT5 installer to finish..."
# Poll until terminal64.exe appears in the bottle's C: drive
BOTTLE_C_DRIVE="$HOME/.var/app/com.usebottles.bottles/data/bottles/$BOTTLE_NAME/drive_c"
MT5_BINARY="$BOTTLE_C_DRIVE/Program Files/MetaTrader 5/terminal64.exe"

TRIES=0
while [ ! -f "$MT5_BINARY" ] && [ $TRIES -lt 60 ]; do
    sleep 5
    TRIES=$((TRIES + 1))
    log "  Waiting for terminal64.exe... ($((TRIES * 5))s)"
done

if [ -f "$MT5_BINARY" ]; then
    log "✓ MT5 installed successfully at: $MT5_BINARY"
else
    log "⚠ terminal64.exe not found after 5 min."
    log "  The installer may still be running, or the path may differ."
    log "  Check: ls \"$BOTTLE_C_DRIVE/Program Files/\""
fi

# ── Symlink mt5-data MQL5 dirs into the bottle ───────────────
# This makes EAs/scripts placed in the host volume immediately
# visible inside the Wine prefix without rebuilding the image.
log "Linking /home/trader/mt5-data MQL5 dirs into the bottle..."

MT5_MQL5="$BOTTLE_C_DRIVE/Program Files/MetaTrader 5/MQL5"
HOST_MQL5="/home/trader/mt5-data/MQL5"

for dir in Experts Scripts Indicators; do
    if [ -d "$MT5_MQL5/$dir" ]; then
        # Back up any existing content
        cp -rn "$MT5_MQL5/$dir/." "$HOST_MQL5/$dir/" 2>/dev/null || true
        rm -rf "$MT5_MQL5/$dir"
    fi
    ln -sfn "$HOST_MQL5/$dir" "$MT5_MQL5/$dir"
    log "  ✓ Linked $dir"
done

log "════════════════════════════════════"
log "  First-run setup complete!"
log "════════════════════════════════════"
