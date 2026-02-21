#!/bin/bash
# ================================================================
# write-config.sh
# Writes terminal.ini into the MT5 portable config directory
# using credentials passed via environment variables.
#
# Environment variables read:
#   MT5_SERVER    — broker server address (e.g. ICMarkets-Demo)
#   MT5_LOGIN     — account number
#   MT5_PASSWORD  — account password
#
# MT5 will show its full UI on the Xvfb display — verify via VNC.
# ================================================================

BOTTLE_NAME="metatrader5"
BOTTLE_C="$HOME/.var/app/com.usebottles.bottles/data/bottles/$BOTTLE_NAME/drive_c"
CONFIG_DIR="$BOTTLE_C/Program Files/MetaTrader 5/config"

mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_DIR/terminal.ini" << EOF
[Login]
Login=${MT5_LOGIN}
Password=${MT5_PASSWORD}
Server=${MT5_SERVER}

[Experts]
; Allow EAs to trade automatically
ExpertsEnable=1
ExpertsDllImport=1
ExpertsDllImport64=1
ExpertsExpImport=0
EOF

echo "[CONFIG] terminal.ini written for login ${MT5_LOGIN} @ ${MT5_SERVER}"
