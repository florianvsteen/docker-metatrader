#!/bin/bash

log() { echo "[$(date '+%H:%M:%S')] $1"; }
log "Running as: $(whoami) uid=$(id -u)"

export DISPLAY=:99
export WINEPREFIX=/home/trader/.mt5
export WINEDEBUG=-all
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

# Auto-dismiss Wine popups (Mono/Gecko dialogs) by pressing Enter
auto_click_dialogs() {
    while true; do
        xdotool search --name "Wine Mono Installer" key Return 2>/dev/null
        xdotool search --name "Wine Gecko Installer" key Return 2>/dev/null
        xdotool search --name "Dialog" key Return 2>/dev/null
        sleep 2
    done
}
auto_click_dialogs &
AUTO_CLICK_PID=$!

# [1/5] Initialize Wine prefix with win10 environment
if [ ! -f "$WINEPREFIX/drive_c/windows/system32/kernel32.dll" ]; then
    log "[1/5] Initialising Wine prefix..."
    # Set win10 mode and boot — this creates the full prefix including kernel32.dll
    wine reg add "HKEY_CURRENT_USER\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f 2>/dev/null || true
    # wineboot initialises the prefix; run in bg and poll for kernel32.dll
    wineboot -u &
    for i in $(seq 1 60); do
        [ -f "$WINEPREFIX/drive_c/windows/system32/kernel32.dll" ] && \
            log "[1/5] Wine prefix ready." && break
        sleep 2
        log "  ...initialising Wine (${i}/60)"
    done
    wineserver -w 2>/dev/null || true
else
    log "[1/5] Wine prefix already initialised."
fi

# [2/5] Install Wine Mono (required for .NET — MT5 needs this)
if [ ! -d "$WINEPREFIX/drive_c/windows/mono" ]; then
    log "[2/5] Downloading Wine Mono..."
    curl -L -o "$TMPDIR/mono.msi" \
        "https://dl.winehq.org/wine/wine-mono/10.3.0/wine-mono-10.3.0-x86.msi"
    log "[2/5] Installing Wine Mono..."
    WINEDLLOVERRIDES="mscoree=d" wine msiexec /i "$TMPDIR/mono.msi" /qn
    wineserver -w
    sleep 3
    rm -f "$TMPDIR/mono.msi"
    log "[2/5] Mono done."
else
    log "[2/5] Mono already installed."
fi

# [3/5] Install MetaTrader 5
if [ ! -f "$MT5_EXE" ]; then
    log "[3/5] Downloading MT5 setup..."
    curl -L -o "$TMPDIR/mt5setup.exe" \
        "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"

    log "[3/5] Running MT5 installer..."
    wine "$TMPDIR/mt5setup.exe" /auto &

    log "[3/5] Waiting for MT5 to install (up to 5 min)..."
    for i in $(seq 1 60); do
        [ -f "$MT5_EXE" ] && log "[3/5] MT5 installed!" && break
        sleep 5
        log "  ...waiting (${i}/60) | wine procs: $(ps aux | grep -c '[w]ine')"
    done

    rm -f "$TMPDIR/mt5setup.exe"

    if [ ! -f "$MT5_EXE" ]; then
        log "[3/5] Not at expected path, searching..."
        found=$(find "$WINEPREFIX" -name "terminal64.exe" 2>/dev/null | head -1)
        if [ -n "$found" ]; then
            log "[3/5] Found at: $found"
            MT5_EXE="$found"
        else
            log "[3/5] ERROR: MT5 not found. drive_c contents:"
            ls -la "$WINEPREFIX/drive_c/Program Files/" 2>/dev/null
            exit 1
        fi
    fi
else
    log "[3/5] MT5 already installed."
fi

kill $AUTO_CLICK_PID 2>/dev/null

# [4/5] Install Python in Wine + packages
if ! wine python --version &>/dev/null 2>&1; then
    log "[4/5] Installing Python in Wine..."
    curl -L -o "$TMPDIR/python.exe" \
        "https://www.python.org/ftp/python/3.9.13/python-3.9.13.exe"
    wine "$TMPDIR/python.exe" /quiet InstallAllUsers=1 PrependPath=1
    wineserver -w
    sleep 5
    rm -f "$TMPDIR/python.exe"
    log "[4/5] Python done."
else
    log "[4/5] Wine Python already installed."
fi

log "[4/5] Installing Wine Python packages..."
wine python -m pip install --upgrade pip -q
wine python -m pip install MetaTrader5==$METATRADER_VERSION mt5linux -q
log "[4/5] Done."

# [5/5] Write auto-login config and launch MT5
if [ -n "$MT5_USER" ]; then
    log "[5/5] Writing auto-login config for $MT5_USER..."
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
    log "[5/5] No MT5_USER set — launching without auto-login (log in via VNC)."
    wine "$MT5_EXE" /portable &
fi

log "Starting mt5linux bridge on port $MT5_SERVER_PORT..."
python3 -m mt5linux --host 0.0.0.0 -p "$MT5_SERVER_PORT" -w wine python.exe
