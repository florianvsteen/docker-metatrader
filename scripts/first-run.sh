#!/bin/bash
# ================================================================
# first-run.sh — Native Bottles (Arch AUR, no Flatpak)
# ================================================================
set -euo pipefail

INSTALLER="/home/trader/mt5setup.exe"
BOTTLES_DATA="/home/trader/.local/share/bottles"
BOTTLE_NAME="metatrader5"

log() { echo "[SETUP $(date '+%H:%M:%S')] $*"; }

export DISPLAY=:99
export XDG_DATA_HOME=/home/trader/.local/share
export HOME=/home/trader

# ── Init D-Bus session ────────────────────────────────────────
eval "$(dbus-launch --sh-syntax 2>/dev/null)" || true

# ── Create Bottle ─────────────────────────────────────────────
log "Creating bottle '$BOTTLE_NAME' (Windows 10, win64)..."
log "This will take 5–10 minutes on first run..."

bottles-cli new \
    --bottle-name "$BOTTLE_NAME" \
    --environment custom \
    --arch win64

log "✓ Bottle created."

# ── Install dependencies ──────────────────────────────────────
log "Installing vcrun2019..."
bottles-cli install-dep --bottle-name "$BOTTLE_NAME" --dep vcrun2019
log "✓ vcrun2019 done."

log "Installing dotnet48..."
bottles-cli install-dep --bottle-name "$BOTTLE_NAME" --dep dotnet48
log "✓ dotnet48 done."

# ── Silent MT5 install ────────────────────────────────────────
log "Running MT5 installer silently..."
bottles-cli run --bottle-name "$BOTTLE_NAME" --exec "$INSTALLER" -- /S

# Poll for terminal64.exe
MT5_BINARY="$BOTTLES_DATA/bottles/$BOTTLE_NAME/drive_c/Program Files/MetaTrader 5/terminal64.exe"
log "Waiting for MT5 installation to complete..."
TRIES=0
while [ ! -f "$MT5_BINARY" ] && [ $TRIES -lt 60 ]; do
    sleep 5
    TRIES=$((TRIES + 1))
    log "  Waiting... ($((TRIES * 5))s)"
done

if [ -f "$MT5_BINARY" ]; then
    log "✓ MT5 installed: $MT5_BINARY"
else
    log "⚠ terminal64.exe not found after 5 min."
    log "  Check: ls \"$BOTTLES_DATA/bottles/$BOTTLE_NAME/drive_c/Program Files/\""
    exit 1
fi

# ── Symlink MQL5 dirs to host volume ─────────────────────────
log "Linking host mql5/ dirs into Bottle..."
MT5_MQL5="$BOTTLES_DATA/bottles/$BOTTLE_NAME/drive_c/Program Files/MetaTrader 5/MQL5"
HOST_MQL5="/home/trader/mt5-data/MQL5"

for dir in Experts Scripts Indicators; do
    if [ -d "$MT5_MQL5/$dir" ]; then
        cp -rn "$MT5_MQL5/$dir/." "$HOST_MQL5/$dir/" 2>/dev/null || true
        rm -rf "$MT5_MQL5/$dir"
    fi
    ln -sfn "$HOST_MQL5/$dir" "$MT5_MQL5/$dir"
    log "  ✓ Linked MQL5/$dir"
done

log "════════════════════════════════════"
log "  First-run setup complete!"
log "════════════════════════════════════"
