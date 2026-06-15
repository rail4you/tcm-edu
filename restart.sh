#!/bin/bash
# Restart local development servers (Phoenix + Next.js)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PHOENIX_PORT=4011
NEXT_PORT=3000

case "${1:-restart}" in
  restart)
    echo "=== Stopping servers ==="
    lsof -ti:$PHOENIX_PORT | xargs kill -9 2>/dev/null || true
    lsof -ti:$NEXT_PORT | xargs kill -9 2>/dev/null || true
    sleep 2

    echo "=== Starting Phoenix (:4011) ==="
    cd "$SCRIPT_DIR" && mix phx.server &
    sleep 6

    echo "=== Starting Next.js (:3000) ==="
    cd "$SCRIPT_DIR/frontend" && pnpm dev 2>/dev/null &
    sleep 4

    echo ""
    echo "✅ Phoenix: http://localhost:$PHOENIX_PORT"
    echo "✅ Next.js: http://localhost:$NEXT_PORT"
    echo "   Chat:    http://localhost:$NEXT_PORT/chat"
    ;;
  stop)
    echo "Stopping servers..."
    lsof -ti:$PHOENIX_PORT | xargs kill -9 2>/dev/null || true
    lsof -ti:$NEXT_PORT | xargs kill -9 2>/dev/null || true
    echo "✅ Stopped"
    ;;
  status)
    echo "Phoenix (:4011): $(lsof -ti:$PHOENIX_PORT >/dev/null 2>&1 && echo '✅ running' || echo '❌ stopped')"
    echo "Next.js (:3000): $(lsof -ti:$NEXT_PORT >/dev/null 2>&1 && echo '✅ running' || echo '❌ stopped')"
    ;;
  *)
    echo "Usage: ./restart.sh [restart|stop|status]"
    ;;
esac
