#!/bin/bash

log() { echo "[$(date '+%H:%M:%S')] $1"; }
log "Running as: $(whoami) uid=$(id -u)"

export DISPLAY=:99
export WINEPREFIX=/home/trader/.mt5
export WINEDEBUG=""
export WINEESYNC=0
export WINEFSYNC=0
export HOME=/home/trader

MT5_EXE="$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"
MT5_SERVER_PORT="${MT5_SERVER_PORT:-8001}"
METATRADER_VERSION="${METATRADER_VERSION:-5.0.36}"
TMPDIR=/home/trader/tmp
mkdir -p "$TMPDIR"

# Wait for Xvfb
log "Waiting for display :99..."
for i in $(seq 1 30); do
    xdpyinfo -display :99 &>/dev/null && log "Display ready." && break
    sleep 1
done

# [1/6] Initialize Wine prefix
if [ ! -f "$WINEPREFIX/drive_c/windows/system32/kernel32.dll" ]; then
    log "[1/6] Initialising Wine prefix..."
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f 2>/dev/null || true
    wine reg add "HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\AeDebug" /v Auto /t REG_SZ /d "0" /f 2>/dev/null || true
    wineboot -u &
    for i in $(seq 1 60); do
        [ -f "$WINEPREFIX/drive_c/windows/system32/kernel32.dll" ] && \
            log "[1/6] Wine prefix ready." && break
        sleep 2
        log "  ...initialising Wine (${i}/60)"
    done
    wineserver -w 2>/dev/null || true
else
    log "[1/6] Wine prefix already initialised."
fi

# [2/6] Install Mono
if [ ! -d "$WINEPREFIX/drive_c/windows/mono" ]; then
    log "[2/6] Installing Wine Mono..."
    curl -L -o "$TMPDIR/mono.msi" \
        "https://dl.winehq.org/wine/wine-mono/10.3.0/wine-mono-10.3.0-x86.msi"
    WINEDLLOVERRIDES="mscoree=d" wine msiexec /i "$TMPDIR/mono.msi" /qn
    wineserver -w
    sleep 3
    rm -f "$TMPDIR/mono.msi"
    log "[2/6] Mono done."
else
    log "[2/6] Mono already installed."
fi

# [3/6] Install Gecko (provides WinInet — required for mt5setup.exe to download)
if [ ! -f "$WINEPREFIX/drive_c/windows/system32/wine_gecko/Wine Gecko.msi" ] && \
   [ ! -d "$WINEPREFIX/drive_c/windows/system32/gecko" ]; then
    log "[3/6] Installing Wine Gecko (enables WinInet networking)..."
    curl -L -o "$TMPDIR/gecko64.msi" \
        "https://dl.winehq.org/wine/wine-gecko/2.47.4/wine-gecko-2.47.4-x86_64.msi"
    curl -L -o "$TMPDIR/gecko32.msi" \
        "https://dl.winehq.org/wine/wine-gecko/2.47.4/wine-gecko-2.47.4-x86.msi"
    wine msiexec /i "$TMPDIR/gecko64.msi" /qn
    wineserver -w
    sleep 3
    wine msiexec /i "$TMPDIR/gecko32.msi" /qn
    wineserver -w
    sleep 3
    rm -f "$TMPDIR/gecko64.msi" "$TMPDIR/gecko32.msi"
    log "[3/6] Gecko done."
else
    log "[3/6] Gecko already installed."
fi

# [4/6] Install MT5 — now that WinInet works, mt5setup.exe can download
if [ ! -f "$MT5_EXE" ]; then
    log "[4/6] Downloading MT5 setup..."
    curl -L -o "$TMPDIR/mt5setup.exe" \
        "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"

    log "[4/6] Running MT5 installer..."
    wine "$TMPDIR/mt5setup.exe" /auto &

    log "[4/6] Waiting for MT5 to install (up to 8 min)..."
    for i in $(seq 1 96); do
        [ -f "$MT5_EXE" ] && log "[4/6] MT5 installed!" && break
        sleep 5
        log "  ...waiting (${i}/96) | wine procs: $(ps aux | grep -c '[w]ine')"
    done

    rm -f "$TMPDIR/mt5setup.exe"

    if [ ! -f "$MT5_EXE" ]; then
        found=$(find "$WINEPREFIX" -name "terminal64.exe" 2>/dev/null | head -1)
        if [ -n "$found" ]; then
            log "[4/6] Found MT5 at: $found"
            MT5_EXE="$found"
        else
            log "[4/6] ERROR: MT5 not found."
            ls -la "$WINEPREFIX/drive_c/Program Files/" 2>/dev/null
            exit 1
        fi
    fi
else
    log "[4/6] MT5 already installed."
fi

# [5/6] Install Python in Wine + packages
if ! wine python --version &>/dev/null 2>&1; then
    log "[5/6] Installing Python in Wine..."
    curl -L -o "$TMPDIR/python.exe" \
        "https://www.python.org/ftp/python/3.9.13/python-3.9.13.exe"
    wine "$TMPDIR/python.exe" /quiet InstallAllUsers=1 PrependPath=1
    wineserver -w
    sleep 5
    rm -f "$TMPDIR/python.exe"
    log "[5/6] Python done."
else
    log "[5/6] Wine Python already installed."
fi

log "[5/6] Installing Wine Python packages..."
wine python -m pip install --upgrade pip -q
wine python -m pip install MetaTrader5==$METATRADER_VERSION mt5linux -q
log "[5/6] Done."

# [6/6] Launch MT5 + bridge
if [ -n "$MT5_USER" ]; then
    log "[6/6] Writing auto-login config for $MT5_USER..."
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
    log "[6/6] No MT5_USER — launching without auto-login (log in via VNC)."
    wine "$MT5_EXE" /portable &
fi

log "Starting mt5linux bridge on port $MT5_SERVER_PORT..."
python3 -m mt5linux --host 0.0.0.0 -p "$MT5_SERVER_PORT" -w wine python.exe
