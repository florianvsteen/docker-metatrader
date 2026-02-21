# ================================================================
# MetaTrader 5 — Headless + VNC
# Stack: Arch Linux → Bottles (AUR, native) → Wine → MT5
# ================================================================
FROM archlinux:latest

# ── 1. Enable multilib + full upgrade + lib32 ────────────────
RUN echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf && \
    pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed lib32-gcc-libs

# ── 2. Base build tools ──────────────────────────────────────
RUN pacman -S --noconfirm --needed base-devel git wget curl sudo

# ── 3. Wine ──────────────────────────────────────────────────
RUN pacman -S --noconfirm --needed wine wine-mono wine-gecko winetricks cabextract

# ── 4. Display + VNC ─────────────────────────────────────────
RUN pacman -S --noconfirm --needed xorg-server-xvfb xorg-xdpyinfo x11vnc fluxbox xdotool

# ── 5. Python + pip ──────────────────────────────────────────
RUN pacman -S --noconfirm --needed python python-pip python-setuptools

# ── 6. Python packages (pacman) ──────────────────────────────
RUN pacman -S --noconfirm --needed \
    python-gobject \
    python-requests \
    python-yaml \
    python-chardet \
    python-markdown \
    python-pycurl \
    python-orjson \
    python-yara \
    python-argcomplete

# ── 7. Bottles GUI dependencies (pacman) ─────────────────────
RUN pacman -S --noconfirm --needed \
    gtk4 \
    gtksourceview5 \
    libadwaita \
    libportal-gtk4 \
    webkit2gtk-4.1 \
    dconf \
    gamemode \
    imagemagick \
    hicolor-icon-theme \
    p7zip

# ── 8. System tools ───────────────────────────────────────────
RUN pacman -S --noconfirm --needed \
    supervisor \
    dbus \
    inotify-tools \
    procps-ng \
    ttf-liberation \
    noto-fonts

# ── 9. noVNC via pip ─────────────────────────────────────────
RUN pip install --break-system-packages novnc websockify

# ── 10. Build user for AUR ────────────────────────────────────
RUN useradd -m -u 1001 -G wheel -s /bin/bash builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# ── 11. AUR packages (all required by Bottles) ───────────────
USER builder
RUN cd /tmp && git clone https://aur.archlinux.org/python-fvs.git && \
    chown -R builder:builder /tmp/python-fvs && \
    cd /tmp/python-fvs && makepkg -si --noconfirm --skippgpcheck

RUN cd /tmp && git clone https://aur.archlinux.org/python-steamgriddb.git && \
    chown -R builder:builder /tmp/python-steamgriddb && \
    cd /tmp/python-steamgriddb && makepkg -si --noconfirm --skippgpcheck

RUN cd /tmp && git clone https://aur.archlinux.org/vkbasalt-cli.git && \
    chown -R builder:builder /tmp/vkbasalt-cli && \
    cd /tmp/vkbasalt-cli && makepkg -si --noconfirm --skippgpcheck

RUN cd /tmp && git clone https://aur.archlinux.org/python-setuptools-reproducible.git && \
    chown -R builder:builder /tmp/python-setuptools-reproducible && \
    cd /tmp/python-setuptools-reproducible && makepkg -si --noconfirm --skippgpcheck

RUN cd /tmp && git clone https://aur.archlinux.org/patool.git && \
    chown -R builder:builder /tmp/patool && \
    cd /tmp/patool && makepkg -si --noconfirm --skippgpcheck

RUN cd /tmp && git clone https://aur.archlinux.org/python-pathvalidate.git && \
    chown -R builder:builder /tmp/python-pathvalidate && \
    cd /tmp/python-pathvalidate && makepkg -si --noconfirm --skippgpcheck

RUN cd /tmp && git clone https://aur.archlinux.org/icoextract.git && \
    chown -R builder:builder /tmp/icoextract && \
    cd /tmp/icoextract && makepkg -si --noconfirm --skippgpcheck

# ── 12. Install Bottles from AUR ─────────────────────────────
RUN cd /tmp && git clone https://aur.archlinux.org/bottles.git && \
    chown -R builder:builder /tmp/bottles && \
    cd /tmp/bottles && makepkg -si --noconfirm --skippgpcheck

USER root

# ── 13. Create trader user ────────────────────────────────────
RUN useradd -m -u 1000 -s /bin/bash trader

# ── 14. Download MT5 installer ────────────────────────────────
RUN wget -q \
    "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe" \
    -O /home/trader/mt5setup.exe && \
    chown trader:trader /home/trader/mt5setup.exe

# ── 15. VNC dir + fluxbox config ─────────────────────────────
RUN mkdir -p /etc/vnc && \
    mkdir -p /home/trader/.fluxbox && \
    echo "session.screen0.toolbar.visible: false" \
        > /home/trader/.fluxbox/init && \
    chown -R trader:trader /home/trader/.fluxbox

# ── 16. Copy scripts and supervisord config ───────────────────
COPY supervisord.conf /etc/supervisord.conf
COPY scripts/entrypoint.sh   /home/trader/scripts/entrypoint.sh
COPY scripts/mt5-start.sh    /home/trader/scripts/mt5-start.sh
COPY scripts/first-run.sh    /home/trader/scripts/first-run.sh
COPY scripts/write-config.sh /home/trader/scripts/write-config.sh
COPY scripts/tail-logs.sh    /home/trader/scripts/tail-logs.sh
RUN chown -R trader:trader /home/trader/scripts && \
    chmod +x /home/trader/scripts/*.sh

# ── 17. Persistent data directories ──────────────────────────
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
