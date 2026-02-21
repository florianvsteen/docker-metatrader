# ================================================================
# MetaTrader 5 — Headless + VNC
# Stack: Arch Linux → Wine (direct, no Bottles) → MT5
# ================================================================
FROM archlinux:latest

# ── 1. Enable multilib + full upgrade ────────────────────────
RUN echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf && \
    pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed lib32-gcc-libs lib32-glibc

# ── 2. Base tools ─────────────────────────────────────────────
RUN pacman -S --noconfirm --needed base-devel git wget curl sudo

# ── 3. Wine + winetricks ──────────────────────────────────────
RUN pacman -S --noconfirm --needed \
    wine \
    wine-mono \
    wine-gecko \
    winetricks \
    cabextract \
    unzip \
    p7zip

# ── 4. Display + VNC ─────────────────────────────────────────
RUN pacman -S --noconfirm --needed \
    xorg-server-xvfb \
    xorg-xdpyinfo \
    x11vnc \
    fluxbox \
    xdotool

# ── 5. System tools ───────────────────────────────────────────
RUN pacman -S --noconfirm --needed \
    supervisor \
    dbus \
    inotify-tools \
    procps-ng \
    ttf-liberation \
    noto-fonts

# ── 6. noVNC ─────────────────────────────────────────────────
RUN pacman -S --noconfirm --needed python python-pip && \
    pip install --break-system-packages novnc websockify

# ── 7. Create trader user (UID 1000) ─────────────────────────
RUN useradd -m -u 1000 -s /bin/bash trader && \
    echo "trader ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# ── 8. Download MT5 installer ─────────────────────────────────
RUN wget -q \
    "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe" \
    -O /home/trader/mt5setup.exe && \
    chown trader:trader /home/trader/mt5setup.exe

# ── 9. VNC dir + fluxbox config ──────────────────────────────
RUN mkdir -p /etc/vnc && \
    mkdir -p /home/trader/.fluxbox && \
    echo "session.screen0.toolbar.visible: false" \
        > /home/trader/.fluxbox/init && \
    chown -R trader:trader /home/trader/.fluxbox

# ── 10. Copy scripts and supervisord config ───────────────────
COPY supervisord.conf /etc/supervisord.conf
COPY scripts/entrypoint.sh   /home/trader/scripts/entrypoint.sh
COPY scripts/mt5-start.sh    /home/trader/scripts/mt5-start.sh
COPY scripts/first-run.sh    /home/trader/scripts/first-run.sh
COPY scripts/write-config.sh /home/trader/scripts/write-config.sh
COPY scripts/tail-logs.sh    /home/trader/scripts/tail-logs.sh
RUN chown -R trader:trader /home/trader/scripts && \
    chmod +x /home/trader/scripts/*.sh

# ── 11. Persistent data directories ──────────────────────────
RUN mkdir -p \
    /home/trader/mt5-data/MQL5/Experts \
    /home/trader/mt5-data/MQL5/Scripts \
    /home/trader/mt5-data/MQL5/Indicators \
    /home/trader/mt5-data/logs && \
    chown -R trader:trader /home/trader/mt5-data

# ── 12. Wine prefix dir ───────────────────────────────────────
RUN mkdir -p /home/trader/.wine && \
    chown -R trader:trader /home/trader/.wine

ENV MT5_SERVER=""
ENV MT5_LOGIN=""
ENV MT5_PASSWORD=""
ENV VNC_PASSWORD=trader123
ENV VNC_PORT=5901
ENV NOVNC_PORT=6080
ENV DISPLAY=:99
ENV WINEPREFIX=/home/trader/.wine
ENV WINEARCH=win64
ENV WINEDEBUG=-all

VOLUME ["/home/trader/mt5-data"]
VOLUME ["/home/trader/.wine"]

EXPOSE ${VNC_PORT} ${NOVNC_PORT}

ENTRYPOINT ["/home/trader/scripts/entrypoint.sh"]
