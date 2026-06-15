#!/bin/bash
# ============================================================
# deploy.sh - ash-ts-demo 远程服务器管理
# ============================================================
# 在远程服务器上运行：
#   ./deploy.sh up           启动所有服务
#   ./deploy.sh down         停止
#   ./deploy.sh restart      重启
#   ./deploy.sh logs         实时日志
#   ./deploy.sh status       查看状态
#   ./deploy.sh migrate      跑 DB 迁移（执行容器内 bin/migrate）
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

load_env() {
    [ -f "$ENV_FILE" ] || err "缺少 $ENV_FILE，请先 cp .env.example .env"
    set -a; source "$ENV_FILE"; set +a
}

compose() {
    docker-compose -f "$COMPOSE_FILE" "$@"
}

cmd_up() {
    load_env
    info "启动服务..."
    compose up -d

    echo
    ok "服务已启动"
    echo "  应用: http://${PUBLIC_URL:-localhost}:${HOST_PORT:-4000}/"
    echo "  RPC:  http://${PUBLIC_URL:-localhost}:${HOST_PORT:-4000}/api/rpc/run"
}

cmd_down() {
    load_env
    compose down
    ok "已停止"
}

cmd_restart() {
    load_env
    info "重启服务..."
    compose restart
    ok "已重启"
}

cmd_logs() {
    load_env
    compose logs -f --tail=100 "${1:-}"
}

cmd_status() {
    load_env
    compose ps
    echo
    info "镜像信息:"
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}" \
        | grep -E "REPOSITORY|ash-ts-demo" || true
}

cmd_migrate() {
    load_env
    info "在 app 容器内执行 bin/migrate ..."
    compose run --rm app bin/migrate
    ok "迁移完成"
}

case "${1:-status}" in
    up)       cmd_up ;;
    down)     cmd_down ;;
    restart)  cmd_restart ;;
    logs)     cmd_logs "${2:-}" ;;
    status)   cmd_status ;;
    migrate)  cmd_migrate ;;
    *)        sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
