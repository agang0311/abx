#!/bin/bash
# abx-cookie-daemon.sh - Cookie 自动同步守护进程
# 定期检查所有 Chrome 实例并同步 Cookie 到仓库

set -e

PID_FILE="${HOME}/.openclaw/abx-sessions/cookie-daemon.pid"
LOG_FILE="${HOME}/.openclaw/abx-sessions/logs/cookie-daemon.log"
INTERVAL=${1:-300}  # 默认 5 分钟

mkdir -p "$(dirname "$LOG_FILE")"

# 检查是否已在运行
check_running() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Cookie daemon already running (PID: $pid)"
            exit 1
        fi
    fi
}

# 记录日志
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 主循环
run_daemon() {
    echo $$ > "$PID_FILE"
    log "Cookie daemon started (interval: ${INTERVAL}s)"
    
    while true; do
        sleep "$INTERVAL"
        
        local sessions_dir="${HOME}/.openclaw/abx-sessions/sessions"
        [ -d "$sessions_dir" ] || continue
        
        for session_file in "$sessions_dir"/*.json; do
            [ -f "$session_file" ] || continue
            
            local port=$(jq -r '.port // empty' "$session_file" 2>/dev/null)
            local pid=$(jq -r '.pid // empty' "$session_file" 2>/dev/null)
            local session_id=$(jq -r '.session_id // empty' "$session_file" 2>/dev/null)
            
            if [ -n "$port" ] && [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                # Chrome 在运行，同步 Cookie
                ~/.openclaw/workspace/scripts/abx-cookie-auto.sh sync-now "$port" 2>/dev/null && 
                    log "Synced cookies from $session_id (port: $port)" || 
                    log "Failed to sync from $session_id"
            fi
        done
    done
}

# 停止守护进程
stop_daemon() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            rm -f "$PID_FILE"
            log "Cookie daemon stopped"
        else
            echo "Daemon not running"
            rm -f "$PID_FILE"
        fi
    else
        echo "No PID file found"
    fi
}

# 查看状态
status_daemon() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Cookie daemon is running (PID: $pid)"
            echo "Log file: $LOG_FILE"
            echo ""
            echo "Recent logs:"
            tail -20 "$LOG_FILE" 2>/dev/null || echo "No logs yet"
        else
            echo "Daemon not running (stale PID file)"
            rm -f "$PID_FILE"
        fi
    else
        echo "Daemon not running"
    fi
}

# 主入口
case "${1:-}" in
    start)
        check_running
        run_daemon &
        echo "Cookie daemon started (PID: $!)"
        ;;
    stop)
        stop_daemon
        ;;
    restart)
        stop_daemon 2>/dev/null || true
        sleep 1
        check_running
        run_daemon &
        echo "Cookie daemon restarted (PID: $!)"
        ;;
    status)
        status_daemon
        ;;
    run)
        # 前台运行（用于调试）
        run_daemon
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|run}"
        echo ""
        echo "Commands:"
        echo "  start [interval]  - Start daemon in background (default: 300s)"
        echo "  stop              - Stop daemon"
        echo "  restart           - Restart daemon"
        echo "  status            - Check daemon status"
        echo "  run               - Run in foreground (for debugging)"
        echo ""
        echo "Example:"
        echo "  $0 start 600      # Start with 10-minute interval"
        ;;
esac
