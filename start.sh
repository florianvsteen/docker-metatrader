#!/bin/bash

log() { echo "[$(date '+%H:%M:%S')] $1"; }
log "Running as: $(whoami) uid=$(id -u)"

# --- Configuration ---
mt5file='/config/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe'
mono_url="https://dl.winehq.org/wine/wine-mono/10.3.0/wine-mono-10.3.0-x86.msi"
gecko64_url="https://dl.winehq.org/wine/wine-gecko/2.47.4/wine-gecko-2.47.4-x86_64.msi"
gecko32_url="https://dl.winehq.org/wine/wine-gecko/2.47.4/wine-gecko-2.47.4-x86.msi"
python_url="https://www.python.org/ftp/python/3.9.13/python-3.9.13.exe"
metatrader_version="5.0.36"
mt5server_port="8001"
MT5_CMD_OPTIONS="${MT5_CMD_OPTIONS:-}"

export DISPLAY="${DISPLAY:-:1}"
export WINEPREFIX="/config/.wine"
export WINEDEBUG="-all"
export HOME="/config"

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

mkdir -p "$WINEPREFIX"

# [1/7] Install Mono
if [ ! -d "$WINEPREFIX/drive_c/windows/mono" ]; then
    log "[1/7] Downloading Mono..."
    curl -L -o /tmp/mono.msi "$mono_url"
    log "[1/7] Installing Mono..."
    WINEDLLOVERRIDES="mscoree=d" wine msiexec /i /tmp/mono.msi /qn
    wineserver -w
    sleep 5
    rm -f /tmp/mono.msi
    log "[1/7] Mono done."
else
    log "[1/7] Mono already installed, skipping."
fi

# [2/7] Install Wine Gecko (provides WinInet/HTTP for Wine apps)
# Without this, mt5setup.exe cannot download anything — it uses IE's HTTP stack
if [ ! -d "$WINEPREFIX/drive_c/windows/system32/gecko" ] && \
   [ ! -f "$WINEPREFIX/drive_c/windows/system32/mshtml.dll" ]; then
    log "[2/7] Downloading Wine Gecko (enables Wine networking/WinInet)..."
    curl -L -o /tmp/gecko64.msi "$gecko64_url"
    curl -L -o /tmp/gecko32.msi "$gecko32_url"
    log "[2/7] Installing Gecko 64-bit..."
    wine msiexec /i /tmp/gecko64.msi /qn
    wineserver -w
    sleep 3
    log "[2/7] Installing Gecko 32-bit..."
    wine msiexec /i /tmp/gecko32.msi /qn
    wineserver -w
    sleep 3
    rm -f /tmp/gecko64.msi /tmp/gecko32.msi
    log "[2/7] Gecko done."
else
    log "[2/7] Gecko already installed, skipping."
fi

# [3/7] Install MetaTrader 5
if [ ! -e "$mt5file" ]; then
    log "[3/7] Setting Wine to win10 mode..."
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f

    log "[3/7] Downloading MT5 setup..."
    curl -L -o /tmp/mt5setup.exe \
        "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"

    log "[3/7] Running MT5 installer (now with working networking via Gecko)..."
    wine /tmp/mt5setup.exe /auto &

    log "[3/7] Waiting for MT5 (up to 5 min)..."
    MT5_ELAPSED=0
    while [ ! -e "$mt5file" ] && [ $MT5_ELAPSED -lt 300 ]; do
        sleep 5
        MT5_ELAPSED=$((MT5_ELAPSED + 5))
        log "  waiting... (${MT5_ELAPSED}s) | wine procs: $(ps aux | grep -c '[w]ine') | tmp files: $(ls /config/.wine/drive_c/users/abc/AppData/Local/Temp/ 2>/dev/null | wc -l)"
    done

    if [ ! -e "$mt5file" ]; then
        log "[3/7] Not at expected path, searching..."
        found=$(find "$WINEPREFIX" -name "terminal64.exe" 2>/dev/null | head -1)
        if [ -n "$found" ]; then
            log "[3/7] Found at: $found"
            mt5file="$found"
        else
            log "[3/7] ERROR: MT5 not found. Temp dir contents:"
            ls -la "$WINEPREFIX/drive_c/users/abc/AppData/Local/Temp/" 2>/dev/null
            log "Program Files:"
            ls -la "$WINEPREFIX/drive_c/Program Files/" 2>/dev/null
            exit 1
        fi
    fi

    wineserver -w
    rm -f /tmp/mt5setup.exe
    log "[3/7] MT5 installed at: $mt5file"
else
    log "[3/7] MT5 already installed, skipping."
fi

# [4/7] Install Python in Wine
if ! wine python --version &>/dev/null; then
    log "[4/7] Downloading Python..."
    curl -L -o /tmp/python.exe "$python_url"
    log "[4/7] Installing Python in Wine..."
    wine /tmp/python.exe /quiet InstallAllUsers=1 PrependPath=1
    wineserver -w
    sleep 5
    rm -f /tmp/python.exe
    log "[4/7] Python done."
else
    log "[4/7] Python already installed, skipping."
fi

# [5/7] Install Python packages in Wine
log "[5/7] Installing Wine Python packages..."
wine python -m pip install --upgrade pip -q
wine python -m pip install MetaTrader5==$metatrader_version mt5linux -q
log "[5/7] Done."

# [6/7] Launch MT5
log "[6/7] Writing auto-login config..."
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

log "[6/7] Launching MT5..."
wine "$mt5file" /portable "/config:C:\\auto_login.ini" $MT5_CMD_OPTIONS &

# [7/7] Bridge
log "[7/7] Installing mt5linux on host Python..."
pip3 install mt5linux -q --break-system-packages 2>/dev/null || pip3 install mt5linux -q

log "[7/7] Starting mt5linux bridge on port $mt5server_port..."
python3 -m mt5linux --host 0.0.0.0 -p "$mt5server_port" -w wine python.exe &

log "All done."
wait
