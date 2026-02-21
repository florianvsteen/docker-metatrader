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

# Use home dir for downloads — guaranteed writable by trader
TMPDIR=/home/trader/tmp
mkdir -p "$TMPDIR"

# Wait for Xvfb
log "Waiting for display :99..."
for i in $(seq 1 30); do
    xdpyinfo -display :99 &>/dev/null && log "Display ready." && break
    sleep 1
done

# Auto-click Wine dialogs (Mono/Gecko install prompts) in the background
# xdotool watches for the dialog and clicks Install/OK automatically
auto_click_dialogs() {
    while true; do
        # Click any "Install" button that appears
        xdotool search --sync --name "Wine Mono Installer" key Return 2>/dev/null
        xdotool search --sync --name "Wine Gecko Installer" key Return 2>/dev/null
        sleep 2
    done
}
auto_click_dialogs &
AUTO_CLICK_PID=$!

# [1/5] Install Mono manually so it's done before MT5 needs it
if [ ! -d "$WINEPREFIX/drive_c/windows/mono" ]; then
    log "[1/5] Downloading and installing Wine Mono..."
    curl -L -o "$TMPDIR/mono.msi" \
        "https://dl.winehq.org/wine/wine-mono/10.3.0/wine-mono-10.3.0-x86.msi"
    WINEDLLOVERRIDES="mscoree=d" wine msiexec /i "$TMPDIR/mono.msi" /qn
    wineserver -w
    sleep 3
    rm -f "$TMPDIR/mono.msi"
    log "[1/5] Mono done."
else
    log "[1/5] Mono already installed."
fi

# [2/5] Run the official MQL5 Linux install script
if [ ! -f "$MT5_EXE" ]; then
    log "[2/5] Downloading official mt5linux.sh..."
    curl -L -o "$TMPDIR/mt5linux.sh" \
        "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5linux.sh"
    chmod +x "$TMPDIR/mt5linux.sh"

    log "[2/5] Running mt5linux.sh (auto-answering prompts)..."
    # Feed 'y' to any prompts the script asks
    yes | "$TMPDIR/mt5linux.sh" || true

    log "[2/5] Waiting for MT5 to finish installing (up to 5 min)..."
    for i in $(seq 1 60); do
        [ -f "$MT5_EXE" ] && log "[2/5] MT5 installed!" && break
        sleep 5
        log "  ...waiting (${i}/60) | wine procs: $(ps aux | grep -c '[w]ine')"
    done

    rm -f "$TMPDIR/mt5linux.sh"

    if [ ! -f "$MT5_EXE" ]; then
        log "[2/5] ERROR: MT5 not found. Searching..."
        found=$(find "$WINEPREFIX" -name "terminal64.exe" 2>/dev/null | head -1)
        [ -n "$found" ] && mt5file="$found" && log "Found at: $found" || exit 1
    fi
else
    log "[2/5] MT5 already installed."
fi

# Stop auto-click daemon
kill $AUTO_CLICK_PID 2>/dev/null

# [3/5] Install Python in Wine
if ! wine python --version &>/dev/null 2>&1; then
    log "[3/5] Installing Python in Wine..."
    curl -L -o "$TMPDIR/python.exe" \
        "https://www.python.org/ftp/python/3.9.13/python-3.9.13.exe"
    wine "$TMPDIR/python.exe" /quiet InstallAllUsers=1 PrependPath=1
    wineserver -w
    sleep 5
    rm -f "$TMPDIR/python.exe"
    log "[3/5] Python done."
else
    log "[3/5] Wine Python already installed."
fi

# [4/5] Install Python packages in Wine
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
    log "[5/5] No MT5_USER — launching without auto-login."
    wine "$MT5_EXE" /portable &
fi

log "Starting mt5linux bridge on port $MT5_SERVER_PORT..."
python3 -m mt5linux --host 0.0.0.0 -p "$MT5_SERVER_PORT" -w wine python.exe
