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

show_message() { echo "$1"; }

check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        echo "$1 is not installed. Exiting."; exit 1
    fi
}

is_python_package_installed() {
    python3 -c "import pkg_resources; exit(not pkg_resources.require('$1'))" 2>/dev/null
    return $?
}

is_wine_python_package_installed() {
    $wine_executable python -c "import pkg_resources; exit(not pkg_resources.require('$1'))" 2>/dev/null
    return $?
}

check_dependency "curl"
check_dependency "$wine_executable"

# [1/7] Install Mono
if [ ! -e "/config/.wine/drive_c/windows/mono" ]; then
    show_message "[1/7] Installing Mono..."
    curl -o /config/.wine/drive_c/mono.msi "$mono_url"
    WINEDLLOVERRIDES=mscoree=d $wine_executable msiexec /i /config/.wine/drive_c/mono.msi /qn
    rm /config/.wine/drive_c/mono.msi
fi

# [2/7] Install MetaTrader 5
if [ ! -e "$mt5file" ]; then
    show_message "[2/7] Installing MT5..."
    $wine_executable reg add "HKEY_CURRENT_USER\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f
    curl -o /config/.wine/drive_c/mt5setup.exe "$mt5setup_url"
    $wine_executable "/config/.wine/drive_c/mt5setup.exe" "/auto" &
    wait
    rm -f /config/.wine/drive_c/mt5setup.exe
fi

# [4/7] RUN MT5 WITH AUTO-LOGIN
if [ -e "$mt5file" ]; then
    show_message "[4/7] Generating Auto-Login Config..."
    
    # We write line-by-line to avoid Heredoc EOF syntax errors in some shells
    echo "[Common]" > "/config/.wine/drive_c/auto_login.ini"
    echo "Login=$MT5_USER" >> "/config/.wine/drive_c/auto_login.ini"
    echo "Password=$MT5_PASSWORD" >> "/config/.wine/drive_c/auto_login.ini"
    echo "Server=$MT5_SERVER" >> "/config/.wine/drive_c/auto_login.ini"
    echo "ProxyEnable=0" >> "/config/.wine/drive_c/auto_login.ini"
    echo "CertConfirm=0" >> "/config/.wine/drive_c/auto_login.ini"
    echo "[Experts]" >> "/config/.wine/drive_c/auto_login.ini"
    echo "AllowLiveTrading=1" >> "/config/.wine/drive_c/auto_login.ini"
    echo "AllowDLLImport=1" >> "/config/.wine/drive_c/auto_login.ini"

    show_message "[4/7] Launching MT5 for account $MT5_USER..."
    # /portable is key for Docker; /config:C:\... uses our new file
    $wine_executable "$mt5file" /portable "/config:C:\\auto_login.ini" $MT5_CMD_OPTIONS &
else
    show_message "[4/7] MT5 executable not found."
fi

# [5/7] Python & [6/7] Libraries (Original Logic)
if ! $wine_executable python --version &>/dev/null; then
    show_message "[5/7] Installing Python in Wine..."
    curl -L "$python_url" -o /tmp/python-installer.exe
    $wine_executable /tmp/python-installer.exe /quiet InstallAllUsers=1 PrependPath=1
    rm /tmp/python-installer.exe
fi

show_message "[6/7] Finalizing Libraries..."
$wine_executable python -m pip install --upgrade pip
$wine_executable python -m pip install MetaTrader5==$metatrader_version mt5linux

# [7/7] Start the Bridge Server
show_message "[7/7] Starting mt5linux server on port $mt5server_port..."
python3 -m mt5linux --host 0.0.0.0 -p "$mt5server_port" -w "$wine_executable" python.exe &

wait
