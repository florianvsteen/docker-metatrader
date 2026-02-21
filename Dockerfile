# ================================================================
# MetaTrader 5 — Headless Docker Container
# Stack: Ubuntu 22.04 → Flatpak → Bottles → Wine → MT5
# No GUI, no VNC. Runs EAs/scripts via MT5 terminal headlessly.
# ================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Bottles/Flatpak environment
ENV FLATPAK_USER_DIR=/home/trader/.local/share/flatpak
ENV HOME=/home/trader
ENV USER=trader

# MT5 config (override these at runtime via docker-compose env)
ENV MT5_SERVER=""
ENV MT5_LOGIN=""
ENV MT5_PASSWORD=""

# VNC config (override via docker-compose env)
ENV VNC_PASSWORD=trader123
ENV VNC_PORT=5901
ENV NOVNC_PORT=6080
ENV DISPLAY=:99

# ── 1. Base system packages ───────────────────────────────────
RUN apt-get update && apt-get install -y \
    # Flatpak
    flatpak \
    flatpak-xdg-utils \
    bubblewrap \
    ostree \
    # Display + VNC
    xvfb \
    x11vnc \
    fluxbox \
    # noVNC (browser-based VNC viewer)
    novnc \
    websockify \
    # Process supervisor
    supervisor \
    # Utilities
    wget \
    curl \
    ca-certificates \
    procps \
    dbus \
    dbus-x11 \
    libglib2.0-0 \
    # Fonts (prevents Wine font errors in logs)
    fonts-liberation \
    fonts-dejavu-core \
    cabextract \
    # Log watching
    inotify-tools \
    && rm -rf /var/lib/apt/lists/*

# ── 2. Create non-root user ───────────────────────────────────
RUN useradd -m -u 1000 -s /bin/bash trader

# ── 3. Flatpak: add Flathub as system remote ──────────────────
RUN flatpak remote-add --system --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo

# ── 4. Install Bottles (system-wide so trader user can use it) ─
RUN flatpak install -y --system --noninteractive \
    flathub com.usebottles.bottles

# ── 5. Switch to trader user for remaining steps ──────────────
USER trader
WORKDIR /home/trader

# ── 6. Download MT5 installer ─────────────────────────────────
RUN wget -q \
    "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe" \
    -O /home/trader/mt5setup.exe && \
    echo "MT5 installer downloaded."

# ── 7. VNC password (set at build time; overridable at runtime) ──
USER root
RUN mkdir -p /etc/vnc && \
    x11vnc -storepasswd "${VNC_PASSWORD}" /etc/vnc/passwd

# Minimal fluxbox config — just a window manager, no taskbar
RUN mkdir -p /home/trader/.fluxbox && \
    echo "session.screen0.toolbar.visible: false" > /home/trader/.fluxbox/init && \
    chown -R trader:trader /home/trader/.fluxbox

# ── 8. Copy in our scripts and supervisord config ─────────────
COPY --chown=trader:trader scripts/ /home/trader/scripts/
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
RUN chmod +x /home/trader/scripts/*.sh

# ── 9. Persistent data directories ───────────────────────────
# These are declared here so Docker knows to treat them as
# mount-points. Actual persistence comes from docker-compose volumes.
RUN mkdir -p \
    /home/trader/mt5-data/MQL5/Experts \
    /home/trader/mt5-data/MQL5/Scripts \
    /home/trader/mt5-data/MQL5/Indicators \
    /home/trader/mt5-data/logs \
    /home/trader/mt5-data/config

VOLUME ["/home/trader/mt5-data"]

EXPOSE ${VNC_PORT} ${NOVNC_PORT}

# ── 10. Entrypoint ────────────────────────────────────────────
ENTRYPOINT ["/home/trader/scripts/entrypoint.sh"]
