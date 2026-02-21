FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:99
ENV HOME=/home/trader
ENV WINEPREFIX=/home/trader/.mt5

RUN useradd -m -s /bin/bash trader

# Install all dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    x11vnc \
    fluxbox \
    wget \
    curl \
    git \
    ca-certificates \
    gnupg2 \
    software-properties-common \
    python3 \
    python3-pip \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# Clone noVNC and websockify directly from GitHub — apt package paths are unreliable
RUN git clone --depth 1 https://github.com/novnc/noVNC.git /opt/novnc \
    && git clone --depth 1 https://github.com/novnc/websockify.git /opt/novnc/utils/websockify \
    && ln -s /opt/novnc/vnc.html /opt/novnc/index.html

# Install Wine (WineHQ stable — same as mt5linux.sh installs)
RUN dpkg --add-architecture i386 \
    && mkdir -pm755 /etc/apt/keyrings \
    && wget -O /etc/apt/keyrings/winehq-archive.key \
        https://dl.winehq.org/wine-builds/winehq.key \
    && wget -NP /etc/apt/sources.list.d/ \
        https://dl.winehq.org/wine-builds/ubuntu/dists/jammy/winehq-jammy.sources \
    && apt-get update \
    && apt-get install -y --install-recommends winehq-stable \
    && rm -rf /var/lib/apt/lists/*

# Install mt5linux bridge on host Python
RUN pip3 install mt5linux websockify --break-system-packages 2>/dev/null \
    || pip3 install mt5linux websockify

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY start_mt5.sh /home/trader/start_mt5.sh
RUN chmod +x /home/trader/start_mt5.sh \
    && chown -R trader:trader /home/trader

EXPOSE 8080 8001

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
