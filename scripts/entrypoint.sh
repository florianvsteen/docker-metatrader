#!/bin/bash
# ================================================================
# entrypoint.sh
# Minimal setup then hands off to supervisord, which manages:
#   Xvfb → Fluxbox → x11vnc → noVNC → mt5-start.sh
# ================================================================
set -euo pipefail

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# ── Fix volume ownership (Docker volumes mount as root) ───────
# Wine prefix and data dirs need to be owned by trader.
mkdir -p /home/trader/.wine
mkdir -p /home/trader/mt5-data/MQL5/Experts
mkdir -p /home/trader/mt5-data/MQL5/Scripts
mkdir -p /home/trader/mt5-data/MQL5/Indicators
mkdir -p /home/trader/mt5-data/logs
chown -R trader:trader /home/trader/.wine
chown -R trader:trader /home/trader/mt5-data

# ── Write VNC password (done here at runtime, not build time) ─
VNC_PASS="${VNC_PASSWORD:-trader123}"
log "Setting VNC password..."
mkdir -p /etc/vnc
x11vnc -storepasswd "${VNC_PASS}" /etc/vnc/passwd

# ── D-Bus setup ───────────────────────────────────────────────
mkdir -p /run/dbus
chmod 755 /run/dbus
mkdir -p /run/user/1000
chown trader:trader /run/user/1000
chmod 700 /run/user/1000

# Ensure machine-id exists (required by dbus-daemon)
[ -f /etc/machine-id ] || dbus-uuidgen > /etc/machine-id

# ── Log dir for supervisor ────────────────────────────────────
mkdir -p /var/log/supervisor

log "═══════════════════════════════════════════════"
log "  MetaTrader 5 — Headless + VNC"
log "═══════════════════════════════════════════════"
log "  noVNC  →  http://<host>:${NOVNC_PORT:-6080}/vnc.html"
log "  VNC    →  <host>:${VNC_PORT:-5901}"
log "  Logs   →  docker logs -f metatrader5"
log "═══════════════════════════════════════════════"

exec /usr/bin/supervisord -n -c /etc/supervisord.conf
