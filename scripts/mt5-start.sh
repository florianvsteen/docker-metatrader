#!/bin/bash
# ================================================================
# mt5-start.sh
# Run by supervisord as the trader user.
# Handles first-run Bottles setup, config writing, and MT5 launch.
# ================================================================
set -euo pipefail

BOTTLE_NAME="metatrader5"
MT5_EXE="C:\\Program Files\\MetaTrader 5\\terminal64.exe"
INSTALLER="/home/trader/mt5setup.exe"
BOTTLE_FLAG="/home/trader/.bottles_ready"
BOTTLES_CLI="flatpak run --command=bottles-cli com.usebottles.bottles"

# Flatpak inside Docker: disable bubblewrap's own sandboxing
export FLATPAK_BWRAP=/bin/bwrap
export container=docker

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

export DISPLAY=:99
export HOME=/home/trader

# ── D-Bus (Flatpak needs this) ────────────────────────────────
eval "$(dbus-launch --sh-syntax 2>/dev/null)" || true

# ── Wait for Xvfb to be ready ────────────────────────────────
log "Waiting for display :99..."
for i in $(seq 1 20); do
    xdpyinfo -display :99 >/dev/null 2>&1 && break
    sleep 1
done
log "Display ready."

# ── First-run setup ───────────────────────────────────────────
if [ ! -f "$BOTTLE_FLAG" ]; then
    log "════════════════════════════════════════"
    log "  FIRST RUN — Setting up Bottles + MT5"
    log "  This takes 10–15 minutes. Please wait."
    log "════════════════════════════════════════"
    /home/trader/scripts/first-run.sh "$BOTTLE_NAME" "$MT5_EXE" "$INSTALLER"
    touch "$BOTTLE_FLAG"
    log "✓ First-run complete."
fi

# ── Write broker config ───────────────────────────────────────
if [ -n "${MT5_LOGIN:-}" ] && [ -n "${MT5_SERVER:-}" ]; then
    log "Writing terminal.ini (login: ${MT5_LOGIN} @ ${MT5_SERVER})..."
    /home/trader/scripts/write-config.sh
fi

# ── Launch MT5 ────────────────────────────────────────────────
log "════════════════════════════════════════"
log "  Launching MetaTrader 5"
log "  Verify at: http://<host>:${NOVNC_PORT:-6080}/vnc.html"
log "════════════════════════════════════════"

# Start log tailer in background
/home/trader/scripts/tail-logs.sh &

# Launch MT5 — /portable keeps all data in the install dir
$BOTTLES_CLI run \
    --bottle-name "$BOTTLE_NAME" \
    --exec "$MT5_EXE" \
    -- /portable

log "MT5 process exited."
