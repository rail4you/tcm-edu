#!/bin/bash
# Restart local development servers (Phoenix only — frontend 已移除，LiveView 承担全部 UI)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PHOENIX_PORT=4011

case "${1:-restart}" in
  restart)
    echo "=== Stopping Phoenix (:${PHOENIX_PORT}) ==="
    lsof -ti:$PHOENIX_PORT | xargs kill -9 2>/dev/null || true
    sleep 2

    echo "=== Starting Phoenix (:${PHOENIX_PORT}) ==="
    cd "$SCRIPT_DIR" && mix phx.server &

    sleep 6

    echo ""
    echo "✅ Phoenix: http://localhost:$PHOENIX_PORT"
    ;;
  stop)
    echo "Stopping Phoenix..."
    lsof -ti:$PHOENIX_PORT | xargs kill -9 2>/dev/null || true
    echo "✅ Stopped"
    ;;
  status)
    echo "Phoenix (:${PHOENIX_PORT}): $(lsof -ti:$PHOENIX_PORT >/dev/null 2>&1 && echo '✅ running' || echo '❌ stopped')"
    ;;
  *)
    echo "Usage: ./restart.sh [restart|stop|status]"
    ;;
esac