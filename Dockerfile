FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:99
ENV HOME=/home/trader
ENV WINEPREFIX=/home/trader/.mt5

RUN useradd -m -s /bin/bash trader

# Install everything via apt — no external downloads during build
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    x11vnc \
    fluxbox \
    wget \
    curl \
    ca-certificates \
    gnupg2 \
    software-properties-common \
    python3 \
    python3-pip \
    python3-websockify \
    novnc \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# Install Wine
RUN dpkg --add-architecture i386 \
    && mkdir -pm755 /etc/apt/keyrings \
    && wget -O /etc/apt/keyrings/winehq-archive.key \
        https://dl.winehq.org/wine-builds/winehq.key \
    && wget -NP /etc/apt/sources.list.d/ \
        https://dl.winehq.org/wine-builds/ubuntu/dists/jammy/winehq-jammy.sources \
    && apt-get update \
    && apt-get install -y --install-recommends winehq-stable \
    && rm -rf /var/lib/apt/lists/*

# Install mt5linux bridge
RUN pip3 install mt5linux --break-system-packages 2>/dev/null || pip3 install mt5linux

# Find and symlink noVNC to a known location
RUN find / -name "novnc_proxy" 2>/dev/null | head -1 | xargs -I{} ln -sf {} /usr/local/bin/novnc_proxy ; \
    find / -name "*.html" -path "*/novnc/*" 2>/dev/null | head -1 | xargs -I{} dirname {} | xargs -I{} ln -sfn {} /opt/novnc ; \
    true

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY start_mt5.sh /home/trader/start_mt5.sh
RUN chmod +x /home/trader/start_mt5.sh \
    && chown -R trader:trader /home/trader

EXPOSE 8080 8001

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
