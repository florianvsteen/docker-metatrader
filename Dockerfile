# ================================================================
# MetaTrader 5 — Headless + VNC
# Stack: Arch Linux → Bottles (AUR, native) → Wine → MT5
#
# Uses Arch Linux so Bottles can be installed natively via AUR
# without Flatpak/bubblewrap — no sandbox conflicts with Docker.
# ================================================================
FROM archlinux:latest

# ── 1. System update + base tools ────────────────────────────
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
        # Build tools (needed for AUR)
        base-devel \
        git \
        # Wine (multilib)
        wine \
        wine-mono \
        wine-gecko \
        # Bottles dependencies (from AUR PKGBUILD)
        python \
        python-gobject \
        python-requests \
        python-yaml \
        python-markdown \
        python-patool \
        python-pycurl \
        python-chardet \
        cabextract \
        p7zip \
        # Display + VNC
        xorg-server-xvfb \
        x11vnc \
        fluxbox \
        xdotool \
        xorg-xdpyinfo \
        # noVNC
        python-pip \
        websockify \
        # Process management
        supervisor \
        # D-Bus
        dbus \
        # Utilities
        wget \
        curl \
        inotify-tools \
        procps-ng \
        # Fonts
        ttf-liberation \
        ttf-dejavu \
    && pacman -Scc --noconfirm

# ── 2. Enable multilib repo (needed for 32-bit Wine) ─────────
RUN echo "[multilib]" >> /etc/pacman.conf && \
    echo "Include = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf && \
    pacman -Sy --noconfirm && \
    pacman -S --noconfirm \
        lib32-gcc-libs \
        lib32-gnutls \
    && pacman -Scc --noconfirm

# ── 3. Install noVNC via pip ──────────────────────────────────
RUN pip install --break-system-packages novnc 2>/dev/null || \
    pip install novnc 2>/dev/null || true
# Also try the package directly
RUN pacman -S --noconfirm python-novnc 2>/dev/null || true

# ── 4. Create build user (makepkg refuses to run as root) ─────
RUN useradd -m -G wheel -s /bin/bash builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# ── 5. Create trader user ─────────────────────────────────────
RUN useradd -m -u 1000 -s /bin/bash trader

# ── 6. Install Bottles from AUR as builder user ───────────────
USER builder
RUN cd /tmp && \
    git clone https://aur.archlinux.org/bottles.git && \
    cd bottles && \
    # Install all AUR deps that aren't in pacman first
    makepkg -si --noconfirm --skippgpcheck 2>&1

USER root

# ── 7. Download MT5 installer ─────────────────────────────────
RUN wget -q \
    "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe" \
    -O /home/trader/mt5setup.exe && \
    chown trader:trader /home/trader/mt5setup.exe

# ── 8. VNC dir + fluxbox config ──────────────────────────────
RUN mkdir -p /etc/vnc && \
    mkdir -p /home/trader/.fluxbox && \
    echo "session.screen0.toolbar.visible: false" \
        > /home/trader/.fluxbox/init && \
    chown -R trader:trader /home/trader/.fluxbox

# ── 9. Copy scripts and supervisord config ───────────────────
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY scripts/entrypoint.sh   /home/trader/scripts/entrypoint.sh
COPY scripts/mt5-start.sh    /home/trader/scripts/mt5-start.sh
COPY scripts/first-run.sh    /home/trader/scripts/first-run.sh
COPY scripts/write-config.sh /home/trader/scripts/write-config.sh
COPY scripts/tail-logs.sh    /home/trader/scripts/tail-logs.sh
RUN chown -R trader:trader /home/trader/scripts && \
    chmod +x /home/trader/scripts/*.sh

# ── 10. Persistent data directories ──────────────────────────
RUN mkdir -p \
    /home/trader/mt5-data/MQL5/Experts \
    /home/trader/mt5-data/MQL5/Scripts \
    /home/trader/mt5-data/MQL5/Indicators \
    /home/trader/mt5-data/logs && \
    chown -R trader:trader /home/trader/mt5-data

# MT5 config
ENV MT5_SERVER=""
ENV MT5_LOGIN=""
ENV MT5_PASSWORD=""
# VNC config
ENV VNC_PASSWORD=trader123
ENV VNC_PORT=5901
ENV NOVNC_PORT=6080
ENV DISPLAY=:99
# Bottles data dir (native install, not Flatpak)
ENV BOTTLES_DATA=/home/trader/.local/share/bottles
ENV XDG_DATA_HOME=/home/trader/.local/share

VOLUME ["/home/trader/mt5-data"]
VOLUME ["/home/trader/.local/share/bottles"]

EXPOSE ${VNC_PORT} ${NOVNC_PORT}

ENTRYPOINT ["/home/trader/scripts/entrypoint.sh"]
