#!/bin/bash
# ================================================================
# entrypoint.sh
# Minimal setup then hands off to supervisord, which manages:
#   Xvfb → Fluxbox → x11vnc → noVNC → mt5-start.sh
# ================================================================
set -euo pipefail

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# ── Update VNC password if overridden at runtime ──────────────
if [ -n "${VNC_PASSWORD:-}" ]; then
    x11vnc -storepasswd "${VNC_PASSWORD}" /etc/vnc/passwd
fi

# ── D-Bus setup for Flatpak ───────────────────────────────────
mkdir -p /run/user/1000
chown trader:trader /run/user/1000
chmod 700 /run/user/1000

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

exec /usr/bin/supervisord -n -c /etc/supervisor/conf.d/supervisord.conf
