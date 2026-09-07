#!/bin/bash
# ============================================================
# deploy.sh - 一键构建、推送、远程部署
# ============================================================
#
# 1. 本地 Mac 通过 buildx 交叉构建 linux/amd64 镜像
# 2. 推送到阿里云容器镜像仓库
# 3. 同步部署文件到远程服务器
# 4. 远程拉取新镜像、跑迁移、重启容器
#
# 用法:
#   ./deploy.sh                   完整流程 (build + push + deploy + migrate)
#   ./deploy.sh build             仅构建+推送
#   ./deploy.sh remote            仅同步+远程部署 (不重新构建)
#   ./deploy.sh status            查看远程状态
#   ./deploy.sh logs              查看远程日志
#   ./deploy.sh migrate           远程 DB 迁移
#
# 可覆盖变量:
#   PLATFORM=linux/amd64
#   IMAGE=registry.cn-zhangjiakou.aliyuncs.com/myelixir/tcm-edu:latest
#   REMOTE_HOST=ubuntu@119.45.170.4
#   REMOTE_DIR=~/tcm-edu
# ============================================================

set -e

# ─── 配置 ──────────────────────────────────────────────────────
PLATFORM="${PLATFORM:-linux/amd64}"
IMAGE="${IMAGE:-registry.cn-zhangjiakou.aliyuncs.com/myelixir/tcm-edu:latest}"
REMOTE_HOST="${REMOTE_HOST:-ubuntu@119.45.170.4}"
REMOTE_DIR="${REMOTE_DIR:-~/tcm-edu}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_FILES_DIR="$SCRIPT_DIR/etc/docker"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC}  $1"; }
ok()    { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
step()  { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

# ─── 前置检查 ──────────────────────────────────────────────────
preflight() {
    command -v docker >/dev/null 2>&1 || err "请先安装 Docker"
    command -v ssh   >/dev/null 2>&1 || err "请先安装 SSH 客户端"

    if ! docker buildx version >/dev/null 2>&1; then
        err "docker buildx 不可用，请升级 Docker Desktop"
    fi
}

# ─── 构建 + 推送 ──────────────────────────────────────────────
cmd_build() {
    preflight

    if ! docker buildx inspect default >/dev/null 2>&1; then
        docker buildx create --name default --use || true
    fi

    echo ""
    info "============================================"
    info " 平台:   ${PLATFORM}"
    info " 镜像:   ${IMAGE}"
    info " 本机:   $(uname -m)"
    info "============================================"
    echo ""

    START=$(date +%s)

    info "开始构建镜像 (${PLATFORM}) ..."
    docker buildx build \
        --platform "${PLATFORM}" \
        -t "${IMAGE}" \
        --load \
        "$SCRIPT_DIR"

    ELAPSED=$(($(date +%s) - START))
    ok "构建完成 (${ELAPSED}s)"

    echo ""
    docker images "${IMAGE}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"

    echo ""
    info "推送镜像到仓库 ..."
    START=$(date +%s)

    docker push "${IMAGE}"

    ELAPSED=$(($(date +%s) - START))
    ok "推送完成 (${ELAPSED}s)"
}

# ─── 同步部署文件到远程 ──────────────────────────────────────
sync_files() {
    step "同步部署文件到 ${REMOTE_HOST}:${REMOTE_DIR}"

    ssh "$REMOTE_HOST" "mkdir -p ${REMOTE_DIR}"

    scp "$DEPLOY_FILES_DIR/docker-compose.yml" \
        "$DEPLOY_FILES_DIR/.env.example" \
        "$DEPLOY_FILES_DIR/deploy.sh" \
        "$REMOTE_HOST:${REMOTE_DIR}/"

    ok "文件同步完成"
}

# ─── 远程部署 ──────────────────────────────────────────────────
cmd_remote() {
    step "远程拉取镜像并重启容器"

    ssh "$REMOTE_HOST" <<'REMOTE_SCRIPT'
set -e
cd ~/tcm-edu

# 确保 .env 存在
if [ ! -f .env ]; then
    echo '[WARN] .env 不存在，从 .env.example 复制'
    cp .env.example .env
    echo '请编辑 .env 填入 SECRET_KEY_BASE、TOKEN_SIGNING_SECRET 和 DATABASE_URL'
fi

set -a; source .env; set +a

# 拉取最新镜像
echo '>>> 拉取最新镜像...'
docker pull ${IMAGE:-registry.cn-zhangjiakou.aliyuncs.com/myelixir/tcm-edu:latest}

# 停止旧容器
echo '>>> 停止旧容器...'
docker rm -f tcm-edu 2>/dev/null || true

# 启动新容器
echo '>>> 启动新容器...'
docker run -d \
  --name tcm-edu \
  --hostname tcm-edu \
  --network knowledgehub_abp-network \
  --restart unless-stopped \
  -p ${HOST_PORT:-4000}:4000 \
  -e PHX_SERVER=true \
  -e PORT=4000 \
  -e PHX_HOST=${PHX_HOST:-0.0.0.0} \
  -e DATABASE_URL="${DATABASE_URL}" \
  -e POOL_SIZE=${POOL_SIZE:-10} \
  -e SECRET_KEY_BASE="${SECRET_KEY_BASE}" \
  -e TOKEN_SIGNING_SECRET="${TOKEN_SIGNING_SECRET}" \
  -e TZ=${TZ:-Asia/Shanghai} \
  -e LANG=C.UTF-8 \
  ${IMAGE:-registry.cn-zhangjiakou.aliyuncs.com/myelixir/tcm-edu:latest}

echo '>>> 清理旧镜像...'
docker image prune -f 2>/dev/null || true

echo ''
echo '>>> 容器状态:'
docker ps --filter name=tcm-edu --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
REMOTE_SCRIPT

    ok "远程部署完成"
}

# ─── 远程状态 ──────────────────────────────────────────────────
cmd_status() {
    ssh "$REMOTE_HOST" "
echo '=== 容器状态 ==='
docker ps --filter name=tcm-edu --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
echo ''
echo '=== 镜像信息 ==='
docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}' \
    | grep -E 'REPOSITORY|tcm-edu|myelixir' || true
"
}

# ─── 远程日志 ──────────────────────────────────────────────────
cmd_logs() {
    ssh "$REMOTE_HOST" "docker logs -f --tail=${1:-100} tcm-edu"
}

# ─── 远程 DB 迁移 ──────────────────────────────────────────────
cmd_migrate() {
    step "远程执行 DB 迁移 (ash.migrate)"

    ssh "$REMOTE_HOST" <<'REMOTE_MIGRATE'
set -e
cd ~/tcm-edu
set -a; source .env; set +a

docker run --rm \
  --network knowledgehub_abp-network \
  -e MIX_ENV=prod \
  -e DATABASE_URL="${DATABASE_URL}" \
  -e SECRET_KEY_BASE="${SECRET_KEY_BASE}" \
  -e TOKEN_SIGNING_SECRET="${TOKEN_SIGNING_SECRET}" \
  -e TZ=${TZ:-Asia/Shanghai} \
  ${IMAGE:-registry.cn-zhangjiakou.aliyuncs.com/myelixir/tcm-edu:latest} \
  /app/bin/migrate
REMOTE_MIGRATE

    ok "迁移完成"
}

# ─── 完整流程 ──────────────────────────────────────────────────
cmd_all() {
    OVERALL_START=$(date +%s)

    cmd_build
    sync_files
    cmd_remote

    # 等待容器启动后执行迁移
    info "等待容器就绪..."
    sleep 5
    cmd_migrate

    OVERALL_ELAPSED=$(($(date +%s) - OVERALL_START))
    echo ""
    ok "全部完成 (${OVERALL_ELAPSED}s) → http://${REMOTE_HOST#*@}:4000/"
}

# ─── 帮助 ──────────────────────────────────────────────────────
show_help() {
    sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
}

# ─── 入口 ──────────────────────────────────────────────────────
case "${1:-all}" in
    all)      cmd_all ;;
    build)    cmd_build ;;
    remote)   sync_files && cmd_remote ;;
    status)   cmd_status ;;
    logs)     cmd_logs "${2:-100}" ;;
    migrate)  cmd_migrate ;;
    -h|--help|help) show_help ;;
    *)        show_help; exit 1 ;;
esac
