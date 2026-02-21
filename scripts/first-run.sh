#!/bin/bash
# ================================================================
# first-run.sh — Direct Wine (no Bottles)
# ================================================================
set -euo pipefail

INSTALLER="/home/trader/mt5setup.exe"
WINEPREFIX="/home/trader/.wine"
MT5_DIR="$WINEPREFIX/drive_c/Program Files/MetaTrader 5"

log() { echo "[SETUP $(date '+%H:%M:%S')] $*"; }

export DISPLAY=:99
export HOME=/home/trader
export WINEPREFIX="$WINEPREFIX"
export WINEARCH=win64
export WINEDEBUG=-all
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus"

# ── Wait for D-Bus ────────────────────────────────────────────
log "Waiting for D-Bus session bus..."
for i in $(seq 1 30); do
    [ -S /run/user/1000/bus ] && break
    sleep 1
done
[ -S /run/user/1000/bus ] && log "✓ D-Bus ready." || log "⚠ D-Bus socket not found, continuing..."

# ── Init Wine prefix ─────────────────────────────────────────
log "Initialising Wine prefix (win64)..."
wineboot --init
log "✓ Wine prefix ready."

# ── Install vcrun2019 via winetricks ─────────────────────────
log "Installing vcrun2019 (Visual C++ 2019 runtime)..."
winetricks --unattended vcrun2019
log "✓ vcrun2019 done."

# ── Install dotnet48 via winetricks ──────────────────────────
log "Installing dotnet48 (.NET Framework 4.8)..."
winetricks --unattended dotnet48
log "✓ dotnet48 done."

# ── Silent MT5 install ───────────────────────────────────────
log "Running MT5 installer silently..."
wine "$INSTALLER" /S

# Poll for terminal64.exe
log "Waiting for MT5 installation to complete..."
TRIES=0
while [ ! -f "$MT5_DIR/terminal64.exe" ] && [ $TRIES -lt 60 ]; do
    sleep 5
    TRIES=$((TRIES + 1))
    log "  Waiting... ($((TRIES * 5))s)"
done

if [ -f "$MT5_DIR/terminal64.exe" ]; then
    log "✓ MT5 installed: $MT5_DIR/terminal64.exe"
else
    log "⚠ terminal64.exe not found after 5 min."
    log "  Contents of Program Files:"
    ls "$WINEPREFIX/drive_c/Program Files/" 2>/dev/null || true
    exit 1
fi

# ── Symlink MQL5 dirs to host volume ─────────────────────────
log "Linking host mql5/ dirs into Wine prefix..."
MT5_MQL5="$MT5_DIR/MQL5"
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
