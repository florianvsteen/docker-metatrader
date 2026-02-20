#!/bin/bash

# --- Configuration ---
mt5file='/config/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe'
WINEPREFIX='/config/.wine'
WINEDEBUG='-all'
wine_executable="wine"
metatrader_version="5.0.36"
mt5server_port="8001"
MT5_CMD_OPTIONS="${MT5_CMD_OPTIONS:-}"
mono_url="https://dl.winehq.org/wine/wine-mono/10.3.0/wine-mono-10.3.0-x86.msi"
python_url="https://www.python.org/ftp/python/3.9.13/python-3.9.13.exe"
mt5setup_url="https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"

export WINEPREFIX
export WINEDEBUG

# DISPLAY must be set for Wine to work — KasmVNC runs on :1
export DISPLAY="${DISPLAY:-:1}"

show_message() { echo "$1"; }

check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        echo "$1 is not installed. Exiting."; exit 1
    fi
}

check_dependency "curl"
check_dependency "$wine_executable"

# FIX: The /config volume persists between container recreations. If a stale
# autostart (e.g. just "xterm") exists from a previous run, overwrite it with
# the correct one from /defaults so it doesn't block the X session on next boot.
if [ -f /defaults/autostart ]; then
    mkdir -p /config/.config/openbox
    cp /defaults/autostart /config/.config/openbox/autostart
fi

# [0/7] Bootstrap the Wine prefix FIRST before any file operations
if [ ! -d "/config/.wine/drive_c" ]; then
    show_message "[0/7] Initialising Wine prefix..."
    wineboot --init
    wineserver --wait
fi

# [1/7] Install Mono
if [ ! -d "/config/.wine/drive_c/windows/mono" ]; then
    show_message "[1/7] Installing Mono..."
    curl -L -o /tmp/mono.msi "$mono_url"
    WINEDLLOVERRIDES=mscoree=d $wine_executable msiexec /i /tmp/mono.msi /qn
    wineserver --wait
    rm -f /tmp/mono.msi
fi

# [2/7] Install MetaTrader 5
if [ ! -e "$mt5file" ]; then
    show_message "[2/7] Installing MT5..."
    $wine_executable reg add "HKEY_CURRENT_USER\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f
    curl -L -o /tmp/mt5setup.exe "$mt5setup_url"

    # MT5's /auto installer spawns a child process and exits early — poll for
    # terminal64.exe to appear (up to 3 minutes).
    $wine_executable /tmp/mt5setup.exe /auto &
    MT5_INSTALL_TIMEOUT=180
    MT5_ELAPSED=0
    show_message "[2/7] Waiting for MT5 installation to complete (up to ${MT5_INSTALL_TIMEOUT}s)..."
    while [ ! -e "$mt5file" ] && [ $MT5_ELAPSED -lt $MT5_INSTALL_TIMEOUT ]; do
        sleep 5
        MT5_ELAPSED=$((MT5_ELAPSED + 5))
        echo "  ...waiting for MT5 (${MT5_ELAPSED}s elapsed)"
    done

    wineserver --wait
    rm -f /tmp/mt5setup.exe

    if [ ! -e "$mt5file" ]; then
        show_message "[2/7] ERROR: MT5 still not found after ${MT5_INSTALL_TIMEOUT}s. Installation failed."
        exit 1
    fi
    show_message "[2/7] MT5 installed successfully."
fi

# [3/7] Install Python in Wine
if ! $wine_executable python --version &>/dev/null; then
    show_message "[3/7] Installing Python in Wine..."
    curl -L "$python_url" -o /tmp/python-installer.exe
    $wine_executable /tmp/python-installer.exe /quiet InstallAllUsers=1 PrependPath=1
    wineserver --wait
    rm -f /tmp/python-installer.exe
fi

# [4/7] Launch MT5 with auto-login
if [ -e "$mt5file" ]; then
    show_message "[4/7] Generating Auto-Login Config..."
    mkdir -p "/config/.wine/drive_c"
    {
        echo "[Common]"
        echo "Login=$MT5_USER"
        echo "Password=$MT5_PASSWORD"
        echo "Server=$MT5_SERVER"
        echo "ProxyEnable=0"
        echo "CertConfirm=0"
        echo "[Experts]"
        echo "AllowLiveTrading=1"
        echo "AllowDLLImport=1"
    } > "/config/.wine/drive_c/auto_login.ini"

    show_message "[4/7] Launching MT5 for account $MT5_USER..."
    $wine_executable "$mt5file" /portable "/config:C:\\auto_login.ini" $MT5_CMD_OPTIONS &
else
    show_message "[4/7] MT5 executable not found — installer may have failed."
    exit 1
fi

# [5/7] Install Wine-side packages
show_message "[5/7] Installing Wine Python packages..."
$wine_executable python -m pip install --upgrade pip --quiet
$wine_executable python -m pip install MetaTrader5==$metatrader_version mt5linux --quiet

# [6/7] Install mt5linux on HOST Python (needed to run the bridge server)
show_message "[6/7] Installing mt5linux on host Python..."
pip3 install mt5linux --quiet --break-system-packages 2>/dev/null || pip3 install mt5linux --quiet

# [7/7] Start the RPyC bridge server
show_message "[7/7] Starting mt5linux server on port $mt5server_port..."
python3 -m mt5linux --host 0.0.0.0 -p "$mt5server_port" -w "$wine_executable" python.exe &

wait
