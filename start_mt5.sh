#!/bin/bash

log() { echo "[$(date '+%H:%M:%S')] $1"; }

export DISPLAY=:99
export WINEPREFIX=/home/trader/.mt5
export WINEDEBUG=-all
export HOME=/home/trader

MT5_EXE="$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"
MT5_USER="${MT5_USER:-}"
MT5_PASSWORD="${MT5_PASSWORD:-}"
MT5_SERVER="${MT5_SERVER:-}"
MT5_SERVER_PORT="${MT5_SERVER_PORT:-8001}"
METATRADER_VERSION="${METATRADER_VERSION:-5.0.36}"

# Wait for Xvfb to be ready
log "Waiting for display :99..."
for i in $(seq 1 30); do
    xdpyinfo -display :99 &>/dev/null && log "Display ready." && break
    sleep 1
done

# [1/5] Run the official MQL5 Linux install script
if [ ! -f "$MT5_EXE" ]; then
    log "[1/5] Running official MQL5 Linux install script..."
    # The script is interactive — we pre-answer prompts via expect-style input
    # It installs Wine Mono + Gecko automatically then runs mt5setup.exe
    wget -q https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5linux.sh \
        -O /tmp/mt5linux.sh
    chmod +x /tmp/mt5linux.sh

    # The script installs into ~/.mt5 by default which is our WINEPREFIX
    # Run it and accept all prompts automatically
    echo -e "\n\n\n" | /tmp/mt5linux.sh

    # Poll for MT5 to finish installing (up to 5 min)
    log "[1/5] Waiting for MT5 installation (up to 5 min)..."
    for i in $(seq 1 60); do
        [ -f "$MT5_EXE" ] && log "[1/5] MT5 installed." && break
        sleep 5
        log "  ...waiting (${i}/60)"
    done

    if [ ! -f "$MT5_EXE" ]; then
        log "[1/5] ERROR: MT5 not found after install. Check display and Wine."
        exit 1
    fi
else
    log "[1/5] MT5 already installed, skipping."
fi

# [2/5] Install Python inside Wine
if ! wine python --version &>/dev/null 2>&1; then
    log "[2/5] Installing Python in Wine..."
    curl -L -o /tmp/python.exe \
        "https://www.python.org/ftp/python/3.9.13/python-3.9.13.exe"
    wine /tmp/python.exe /quiet InstallAllUsers=1 PrependPath=1
    wineserver -w
    rm -f /tmp/python.exe
    log "[2/5] Python done."
else
    log "[2/5] Wine Python already installed."
fi

# [3/5] Install MT5 Python packages in Wine
log "[3/5] Installing Wine Python packages..."
wine python -m pip install --upgrade pip -q
wine python -m pip install MetaTrader5==$METATRADER_VERSION mt5linux -q
log "[3/5] Done."

# [4/5] Write auto-login config and launch MT5
if [ -n "$MT5_USER" ]; then
    log "[4/5] Writing auto-login config for $MT5_USER..."
    cat > "$WINEPREFIX/drive_c/auto_login.ini" << INI
[Common]
Login=$MT5_USER
Password=$MT5_PASSWORD
Server=$MT5_SERVER
ProxyEnable=0
CertConfirm=0
[Experts]
AllowLiveTrading=1
AllowDLLImport=1
INI
    wine "$MT5_EXE" /portable "/config:C:\\auto_login.ini" &
else
    log "[4/5] No MT5_USER set — launching MT5 without auto-login (use VNC to log in manually)."
    wine "$MT5_EXE" /portable &
fi

# [5/5] Start RPyC bridge
log "[5/5] Starting mt5linux bridge on port $MT5_SERVER_PORT..."
python3 -m mt5linux --host 0.0.0.0 -p "$MT5_SERVER_PORT" -w wine python.exe
