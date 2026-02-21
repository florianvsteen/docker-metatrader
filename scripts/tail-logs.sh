#!/bin/bash
BOTTLES_DATA="/home/trader/.local/share/bottles"
BOTTLE_NAME="metatrader5"
MT5_APPDATA="$BOTTLES_DATA/bottles/$BOTTLE_NAME/drive_c/users/trader/AppData/Roaming/MetaQuotes/Terminal"
HOST_LOGS="/home/trader/mt5-data/logs"

log() { echo "[LOG-WATCHER $(date '+%H:%M:%S')] $*"; }
log "Waiting for MT5 log directory..."

TRIES=0
while [ $TRIES -lt 12 ]; do
    LOG_DIR=$(find "$MT5_APPDATA" -type d -name "logs" 2>/dev/null | head -1)
    [ -n "$LOG_DIR" ] && break
    sleep 5
    TRIES=$((TRIES + 1))
done

[ -z "$LOG_DIR" ] && LOG_DIR="$HOST_LOGS" && mkdir -p "$LOG_DIR"
log "Tailing: $LOG_DIR"

while true; do
    LATEST=$(find "$LOG_DIR" -name "*.log" 2>/dev/null | sort | tail -1)
    if [ -n "$LATEST" ]; then
        tail -F "$LATEST" 2>/dev/null &
        TAIL_PID=$!
        inotifywait -q -e create "$LOG_DIR" 2>/dev/null
        kill $TAIL_PID 2>/dev/null || true
    else
        sleep 10
    fi
done
