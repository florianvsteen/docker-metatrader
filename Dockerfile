FROM ghcr.io/linuxserver/baseimage-kasmvnc:debianbookworm

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Metatrader Docker:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="gmartin"

ENV TITLE=Metatrader5
ENV WINEPREFIX="/config/.wine"
ENV WINEDEBUG=-all

# Install all packages in a single layer to reduce image size
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    wget \
    curl \
    gnupg2 \
    software-properties-common \
    ca-certificates \
    && mkdir -pm755 /etc/apt/keyrings \
    && wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key \
    && wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/debian/dists/bookworm/winehq-bookworm.sources \
    && dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install --install-recommends -y winehq-stable \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /etc/apt/keyrings/winehq-archive.key

# Copy the main startup script
COPY start.sh /Metatrader/start.sh
RUN chmod +x /Metatrader/start.sh

# Place Openbox config files explicitly — the linuxserver KasmVNC base image
# reads autostart from /etc/xdg/openbox/autostart and menu from the same dir.
# The previous COPY /root / relied on a specific build-context folder structure
# that was silently not working.
COPY autostart /etc/xdg/openbox/autostart
COPY menu.xml  /etc/xdg/openbox/menu.xml

# The linuxserver base image also supports scripts dropped into
# /etc/s6-overlay/s6-rc.d/ but autostart via Openbox is sufficient here.

EXPOSE 3000 8001
VOLUME /config
