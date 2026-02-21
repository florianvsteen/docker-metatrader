# ================================================================
# MetaTrader 5 — Headless + VNC
# Stack: Arch Linux → Bottles (AUR, native) → Wine → MT5
# ================================================================
FROM archlinux:latest

# ── 1. Full system update + enable multilib + all packages ────
# Always combine -Syu with package installs in Arch to avoid
# partial upgrade issues with split RUN layers.
RUN sed -i '/^#\[multilib\]/,/^#Include/{s/^#//}' /etc/pacman.conf && \
    pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
        # Build tools
        base-devel \
        git \
        wget \
        curl \
        # Wine + deps
        wine \
        wine-mono \
        wine-gecko \
        winetricks \
        cabextract \
        lib32-gcc-libs \
        lib32-gnutls \
        # Display + VNC
        xorg-server-xvfb \
        xorg-xdpyinfo \
        x11vnc \
        fluxbox \
        xdotool \
        # Python
        python \
        python-pip \
        python-gobject \
        python-requests \
        python-pyyaml \
        python-chardet \
        python-markdown \
        python-pycurl \
        p7zip \
        # System
        supervisor \
        dbus \
        inotify-tools \
        procps-ng \
        ttf-liberation \
        noto-fonts \
    && pacman -Scc --noconfirm

# ── 2. pip packages not in Arch repos ────────────────────────
RUN pip install --break-system-packages \
    novnc \
    websockify \
    patool

# ── 3. Build user for AUR (makepkg refuses root) ─────────────
RUN useradd -m -G wheel -s /bin/bash builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# ── 4. Install Bottles from AUR ──────────────────────────────
USER builder
RUN cd /tmp && \
    git clone https://aur.archlinux.org/bottles.git && \
    cd bottles && \
    makepkg -si --noconfirm --skippgpcheck
USER root

# ── 5. Create trader user ─────────────────────────────────────
RUN useradd -m -u 1000 -s /bin/bash trader

# ── 6. Download MT5 installer ─────────────────────────────────
RUN wget -q \
    "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe" \
    -O /home/trader/mt5setup.exe && \
    chown trader:trader /home/trader/mt5setup.exe

# ── 7. VNC dir + fluxbox config ──────────────────────────────
RUN mkdir -p /etc/vnc && \
    mkdir -p /home/trader/.fluxbox && \
    echo "session.screen0.toolbar.visible: false" \
        > /home/trader/.fluxbox/init && \
    chown -R trader:trader /home/trader/.fluxbox

# ── 8. Copy scripts and supervisord config ───────────────────
COPY supervisord.conf /etc/supervisord.conf
COPY scripts/entrypoint.sh   /home/trader/scripts/entrypoint.sh
COPY scripts/mt5-start.sh    /home/trader/scripts/mt5-start.sh
COPY scripts/first-run.sh    /home/trader/scripts/first-run.sh
COPY scripts/write-config.sh /home/trader/scripts/write-config.sh
COPY scripts/tail-logs.sh    /home/trader/scripts/tail-logs.sh
RUN chown -R trader:trader /home/trader/scripts && \
    chmod +x /home/trader/scripts/*.sh

# ── 9. Persistent data directories ───────────────────────────
RUN mkdir -p \
    /home/trader/mt5-data/MQL5/Experts \
    /home/trader/mt5-data/MQL5/Scripts \
    /home/trader/mt5-data/MQL5/Indicators \
    /home/trader/mt5-data/logs && \
    chown -R trader:trader /home/trader/mt5-data

ENV MT5_SERVER=""
ENV MT5_LOGIN=""
ENV MT5_PASSWORD=""
ENV VNC_PASSWORD=trader123
ENV VNC_PORT=5901
ENV NOVNC_PORT=6080
ENV DISPLAY=:99
ENV XDG_DATA_HOME=/home/trader/.local/share

VOLUME ["/home/trader/mt5-data"]
VOLUME ["/home/trader/.local/share/bottles"]

EXPOSE ${VNC_PORT} ${NOVNC_PORT}

ENTRYPOINT ["/home/trader/scripts/entrypoint.sh"]
