#!/bin/bash

# --- Configuration ---
mt5file='/config/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe'
mono_url="https://dl.winehq.org/wine/wine-mono/10.3.0/wine-mono-10.3.0-x86.msi"
python_url="https://www.python.org/ftp/python/3.9.13/python-3.9.13.exe"
metatrader_version="5.0.36"
mt5server_port="8001"
MT5_CMD_OPTIONS="${MT5_CMD_OPTIONS:-}"

export DISPLAY="${DISPLAY:-:1}"

log() { echo "[$(date '+%H:%M:%S')] $1"; }

# Run a command as the abc user with correct Wine env
wine_cmd() {
    su -s /bin/bash abc -c "
        export DISPLAY='$DISPLAY'
        export WINEPREFIX='/config/.wine'
        export WINEDEBUG='-all'
        $*
    "
}

# Wait for X
log "Waiting for X display $DISPLAY..."
for i in $(seq 1 60); do
    xdpyinfo -display "$DISPLAY" &>/dev/null && log "Display ready." && break
    sleep 1
done

# Keep autostart fresh
if [ -f /defaults/autostart ]; then
    mkdir -p /config/.config/openbox
    cp /defaults/autostart /config/.config/openbox/autostart
fi

# Ensure Wine prefix dir is owned by abc
mkdir -p /config/.wine
chown -R abc:abc /config/.wine

# [1/6] Install Mono
if [ ! -d "/config/.wine/drive_c/windows/mono" ]; then
    log "[1/6] Downloading Mono..."
    curl -L -o /tmp/mono.msi "$mono_url"
    chown abc:abc /tmp/mono.msi
    log "[1/6] Installing Mono..."
    wine_cmd "WINEDLLOVERRIDES='mscoree=d' wine msiexec /i /tmp/mono.msi /qn"
    wine_cmd "wineserver -w"
    sleep 5
    rm -f /tmp/mono.msi
    log "[1/6] Mono done."
else
    log "[1/6] Mono already installed, skipping."
fi

# [2/6] Install MetaTrader 5
if [ ! -e "$mt5file" ]; then
    log "[2/6] Downloading MT5..."
    wine_cmd "wine reg add 'HKEY_CURRENT_USER\\Software\\Wine' /v Version /t REG_SZ /d 'win10' /f"
    curl -L -o /tmp/mt5setup.exe \
        "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"
    chown abc:abc /tmp/mt5setup.exe

    log "[2/6] Running MT5 installer..."
    wine_cmd "wine /tmp/mt5setup.exe /auto" &

    log "[2/6] Waiting for MT5 (up to 4 min)..."
    MT5_ELAPSED=0
    while [ ! -e "$mt5file" ] && [ $MT5_ELAPSED -lt 240 ]; do
        sleep 5
        MT5_ELAPSED=$((MT5_ELAPSED + 5))
        log "  waiting... (${MT5_ELAPSED}s) | wine procs: $(ps aux | grep -c '[w]ine')"
    done

    if [ ! -e "$mt5file" ]; then
        log "[2/6] Not at expected path, searching..."
        found=$(find /config/.wine -name "terminal64.exe" 2>/dev/null | head -1)
        if [ -n "$found" ]; then
            log "[2/6] Found at: $found"
            mt5file="$found"
        else
            log "[2/6] ERROR: MT5 not found. drive_c contents:"
            ls -la "/config/.wine/drive_c/Program Files/" 2>/dev/null
            exit 1
        fi
    fi

    wine_cmd "wineserver -w"
    rm -f /tmp/mt5setup.exe
    log "[2/6] MT5 installed at: $mt5file"
else
    log "[2/6] MT5 already installed, skipping."
fi

# [3/6] Install Python in Wine
if ! wine_cmd "wine python --version" &>/dev/null; then
    log "[3/6] Downloading Python..."
    curl -L -o /tmp/python.exe "$python_url"
    chown abc:abc /tmp/python.exe
    log "[3/6] Installing Python in Wine..."
    wine_cmd "wine /tmp/python.exe /quiet InstallAllUsers=1 PrependPath=1"
    wine_cmd "wineserver -w"
    sleep 5
    rm -f /tmp/python.exe
    log "[3/6] Python done."
else
    log "[3/6] Python already installed, skipping."
fi

# [4/6] Install Python packages in Wine
log "[4/6] Installing Wine Python packages..."
wine_cmd "wine python -m pip install --upgrade pip -q"
wine_cmd "wine python -m pip install MetaTrader5==$metatrader_version mt5linux -q"
log "[4/6] Done."

# [5/6] Launch MT5
log "[5/6] Writing auto-login config..."
su -s /bin/bash abc -c "cat > '/config/.wine/drive_c/auto_login.ini'" << INI
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

log "[5/6] Launching MT5..."
wine_cmd "wine '$mt5file' /portable '/config:C:\\auto_login.ini' $MT5_CMD_OPTIONS" &

# [6/6] Bridge
log "[6/6] Installing mt5linux on host Python..."
pip3 install mt5linux -q --break-system-packages 2>/dev/null || pip3 install mt5linux -q

log "[6/6] Starting mt5linux bridge on port $mt5server_port..."
su -s /bin/bash abc -c "
    export DISPLAY='$DISPLAY'
    export WINEPREFIX='/config/.wine'
    python3 -m mt5linux --host 0.0.0.0 -p $mt5server_port -w wine python.exe
" &

log "All done."
wait
