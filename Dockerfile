# ================================================================
# MetaTrader 5 — Headless + VNC
# Stack: Arch Linux → Bottles (AUR, native) → Wine → MT5
# ================================================================
FROM archlinux:latest

# ── 1. Enable multilib + upgrade + lib32 (must be one layer) ─
# multilib must be enabled before pacman -Syu and stay in the
# same RUN so the repo config persists into the install step.
RUN sed -i '/^#\[multilib\]/,/^#Include/{s/^#//}' /etc/pacman.conf && \
    pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed lib32-gcc-libs lib32-gnutls

# ── 2. Base build tools ──────────────────────────────────────
RUN pacman -S --noconfirm --needed base-devel git wget curl

# ── 3. Wine ──────────────────────────────────────────────────
RUN pacman -S --noconfirm --needed wine wine-mono wine-gecko winetricks cabextract

# ── 4. Display + VNC ─────────────────────────────────────────
RUN pacman -S --noconfirm --needed xorg-server-xvfb xorg-xdpyinfo x11vnc fluxbox xdotool

# ── 5. Python ────────────────────────────────────────────────
RUN pacman -S --noconfirm --needed python python-pip

# ── 6. Python packages ───────────────────────────────────────
RUN pacman -S --noconfirm --needed python-gobject
RUN pacman -S --noconfirm --needed python-requests
RUN pacman -S --noconfirm --needed python-yaml
RUN pacman -S --noconfirm --needed python-chardet
RUN pacman -S --noconfirm --needed python-markdown
RUN pacman -S --noconfirm --needed python-pycurl
RUN pacman -S --noconfirm --needed p7zip

# ── 7. System tools ──────────────────────────────────────────
RUN pacman -S --noconfirm --needed supervisor dbus inotify-tools procps-ng

# ── 8. Fonts ─────────────────────────────────────────────────
RUN pacman -S --noconfirm --needed ttf-liberation noto-fonts

# ── 9. pip packages ──────────────────────────────────────────
RUN pip install --break-system-packages novnc websockify patool

# ── 10. Build user for AUR (makepkg refuses root) ────────────
RUN useradd -m -G wheel -s /bin/bash builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# ── 11. Install Bottles from AUR ─────────────────────────────
USER builder
RUN cd /tmp && \
    git clone https://aur.archlinux.org/bottles.git && \
    cd bottles && \
    makepkg -si --noconfirm --skippgpcheck
USER root

# ── 12. Create trader user ────────────────────────────────────
RUN useradd -m -u 1000 -s /bin/bash trader

# ── 13. Download MT5 installer ────────────────────────────────
RUN wget -q \
    "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe" \
    -O /home/trader/mt5setup.exe && \
    chown trader:trader /home/trader/mt5setup.exe

# ── 14. VNC dir + fluxbox config ─────────────────────────────
RUN mkdir -p /etc/vnc && \
    mkdir -p /home/trader/.fluxbox && \
    echo "session.screen0.toolbar.visible: false" \
        > /home/trader/.fluxbox/init && \
    chown -R trader:trader /home/trader/.fluxbox

# ── 15. Copy scripts and supervisord config ───────────────────
COPY supervisord.conf /etc/supervisord.conf
COPY scripts/entrypoint.sh   /home/trader/scripts/entrypoint.sh
COPY scripts/mt5-start.sh    /home/trader/scripts/mt5-start.sh
COPY scripts/first-run.sh    /home/trader/scripts/first-run.sh
COPY scripts/write-config.sh /home/trader/scripts/write-config.sh
COPY scripts/tail-logs.sh    /home/trader/scripts/tail-logs.sh
RUN chown -R trader:trader /home/trader/scripts && \
    chmod +x /home/trader/scripts/*.sh

# ── 16. Persistent data directories ──────────────────────────
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
