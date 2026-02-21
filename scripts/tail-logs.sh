#!/bin/bash
# ================================================================
# tail-logs.sh
# Watches MT5 log files and streams them to Docker stdout.
# Run this in the background so logs appear in:
#   docker logs -f metatrader5
# ================================================================

BOTTLE_NAME="metatrader5"
BOTTLE_C="$HOME/.var/app/com.usebottles.bottles/data/bottles/$BOTTLE_NAME/drive_c"

# MT5 writes logs to AppData\Roaming\MetaQuotes\Terminal\<id>\logs\
MT5_APPDATA="$BOTTLE_C/users/trader/AppData/Roaming/MetaQuotes/Terminal"

# Also tail from the host-mounted logs directory
HOST_LOGS="/home/trader/mt5-data/logs"

log() { echo "[LOG-WATCHER $(date '+%H:%M:%S')] $*"; }

log "Waiting for MT5 log directory to appear..."

# Wait up to 60s for MT5 to create its log directory
TRIES=0
while [ $TRIES -lt 12 ]; do
    LOG_DIR=$(find "$MT5_APPDATA" -type d -name "logs" 2>/dev/null | head -1)
    if [ -n "$LOG_DIR" ]; then
        log "Found MT5 log dir: $LOG_DIR"
        break
    fi
    sleep 5
    TRIES=$((TRIES + 1))
done

if [ -z "$LOG_DIR" ]; then
    log "⚠ MT5 log dir not found after 60s. Falling back to host logs dir."
    LOG_DIR="$HOST_LOGS"
    mkdir -p "$LOG_DIR"
fi

log "Tailing logs from: $LOG_DIR"

# Use inotifywait to catch new log files as MT5 rotates them daily
while true; do
    # Tail all current log files
    LATEST=$(find "$LOG_DIR" -name "*.log" 2>/dev/null | sort | tail -1)
    if [ -n "$LATEST" ]; then
        log "Active log file: $(basename "$LATEST")"
        tail -F "$LATEST" 2>/dev/null &
        TAIL_PID=$!
        # Watch for new log files (MT5 creates a new one each day)
        inotifywait -q -e create "$LOG_DIR" 2>/dev/null
        kill $TAIL_PID 2>/dev/null || true
    else
        log "No .log files yet, waiting..."
        sleep 10
    fi
done
