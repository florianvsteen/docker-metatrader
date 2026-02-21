FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV WINEPREFIX=/home/trader/.mt5
ENV DISPLAY=:99
ENV HOME=/home/trader

# Create a non-root user — Wine refuses to run as root
RUN useradd -m -s /bin/bash trader

# Install dependencies:
# - Xvfb: virtual display (Wine needs a display to render)
# - x11vnc: VNC server so we can see what's happening
# - novnc + websockify: browser-based VNC access
# - wget/curl: for downloading installers
# - supervisor: process manager to keep everything running
# - Python3: for the RPyC bridge
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    x11vnc \
    novnc \
    websockify \
    openbox \
    wget \
    curl \
    ca-certificates \
    gnupg2 \
    software-properties-common \
    python3 \
    python3-pip \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# Install Wine from WineHQ (stable) — same as mt5linux.sh would do on Ubuntu
RUN dpkg --add-architecture i386 \
    && mkdir -pm755 /etc/apt/keyrings \
    && wget -O /etc/apt/keyrings/winehq-archive.key \
        https://dl.winehq.org/wine-builds/winehq.key \
    && wget -NP /etc/apt/sources.list.d/ \
        https://dl.winehq.org/wine-builds/ubuntu/dists/jammy/winehq-jammy.sources \
    && apt-get update \
    && apt-get install -y --install-recommends winehq-stable \
    && rm -rf /var/lib/apt/lists/*

# Install mt5linux Python bridge on host
RUN pip3 install mt5linux --break-system-packages 2>/dev/null || pip3 install mt5linux

# Copy config files
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY start_mt5.sh /home/trader/start_mt5.sh
RUN chmod +x /home/trader/start_mt5.sh \
    && chown -R trader:trader /home/trader

EXPOSE 8080 8001

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
