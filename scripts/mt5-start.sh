#!/bin/bash
# ================================================================
# mt5-start.sh — run by supervisord as trader user
# ================================================================
set -euo pipefail

BOTTLE_FLAG="/home/trader/.wine_ready"
WINEPREFIX="/home/trader/.wine"
MT5_EXE="$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

export DISPLAY=:99
export HOME=/home/trader
export WINEPREFIX="$WINEPREFIX"
export WINEARCH=win64
export WINEDEBUG=-all
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus"

# ── Wait for D-Bus session bus ────────────────────────────────
for i in $(seq 1 30); do
    [ -S /run/user/1000/bus ] && break
    sleep 1
done

# ── Wait for Xvfb ─────────────────────────────────────────────
log "Waiting for display :99..."
for i in $(seq 1 30); do
    xdpyinfo -display :99 >/dev/null 2>&1 && break
    sleep 1
done
log "Display ready."

# ── First run ─────────────────────────────────────────────────
if [ ! -f "$BOTTLE_FLAG" ]; then
    log "════════════════════════════════════════"
    log "  FIRST RUN — Installing Wine prefix + MT5"
    log "  This takes 10–20 minutes. Please wait."
    log "════════════════════════════════════════"
    /home/trader/scripts/first-run.sh
    touch "$BOTTLE_FLAG"
    log "✓ First-run complete."
fi

# ── Write broker config ───────────────────────────────────────
if [ -n "${MT5_LOGIN:-}" ] && [ -n "${MT5_SERVER:-}" ]; then
    log "Writing terminal.ini (${MT5_LOGIN} @ ${MT5_SERVER})..."
    /home/trader/scripts/write-config.sh
fi

# ── Launch MT5 ────────────────────────────────────────────────
log "════════════════════════════════════════"
log "  Launching MetaTrader 5"
log "  Verify at: http://<host>:${NOVNC_PORT:-6080}/vnc.html"
log "════════════════════════════════════════"

/home/trader/scripts/tail-logs.sh &

wine "$MT5_EXE" /portable

log "MT5 process exited."
