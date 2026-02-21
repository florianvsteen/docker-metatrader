#!/bin/bash
WINEPREFIX="/home/trader/.wine"
CONFIG_DIR="$WINEPREFIX/drive_c/Program Files/MetaTrader 5/config"
mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_DIR/terminal.ini" << INIEOF
[Login]
Login=${MT5_LOGIN}
Password=${MT5_PASSWORD}
Server=${MT5_SERVER}

[Experts]
ExpertsEnable=1
ExpertsDllImport=1
ExpertsDllImport64=1
ExpertsExpImport=0
INIEOF

echo "[CONFIG] terminal.ini written → ${MT5_LOGIN} @ ${MT5_SERVER}"
