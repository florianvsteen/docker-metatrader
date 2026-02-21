#!/bin/bash
# ================================================================
# entrypoint.sh
# Minimal setup then hands off to supervisord, which manages:
#   Xvfb → Fluxbox → x11vnc → noVNC → mt5-start.sh
# ================================================================
set -euo pipefail

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# ── Write VNC password (done here at runtime, not build time) ─
VNC_PASS="${VNC_PASSWORD:-trader123}"
log "Setting VNC password..."
mkdir -p /etc/vnc
x11vnc -storepasswd "${VNC_PASS}" /etc/vnc/passwd

# ── Fix volume ownership (Docker volumes mount as root) ───────
# Bottles needs trader to own its data dir, but named volumes
# are created by Docker as root. Fix this at every container start.
mkdir -p /home/trader/.local/share/bottles
chown -R trader:trader /home/trader/.local/share
chmod -R 755 /home/trader/.local/share

# Fix the state-flag volume mount point too
mkdir -p /home/trader/.bottles_ready
chown trader:trader /home/trader/.bottles_ready

# ── D-Bus setup ───────────────────────────────────────────────
mkdir -p /run/user/1000
chown trader:trader /run/user/1000
chmod 700 /run/user/1000
# Pre-create dbus system socket dir (needed before dbus-daemon starts)
mkdir -p /run/dbus
chmod 755 /run/dbus

# ── Log dir for supervisor ────────────────────────────────────
mkdir -p /var/log/supervisor

log "═══════════════════════════════════════════════"
log "  MetaTrader 5 — Headless + VNC verification"
log "═══════════════════════════════════════════════"
log "  noVNC  →  http://<host>:${NOVNC_PORT:-6080}/vnc.html"
log "  VNC    →  <host>:${VNC_PORT:-5901}"
log "  VNC is view-only by default (safe for verification)"
log "  Logs   →  docker logs -f metatrader5"
log "═══════════════════════════════════════════════"

exec /usr/bin/supervisord -n -c /etc/supervisord.conf
