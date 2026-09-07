#!/bin/bash
# ============================================================
# build-and-push.sh - 本地 Mac 构建 amd64 镜像并推送到远程仓库
# ============================================================
#
# 在本地 Mac (ARM64) 上通过 docker buildx 交叉构建 linux/amd64
# 镜像，加载到本地 Docker，再推送到阿里云容器镜像仓库。
#
# 用法:
#   ./build-and-push.sh                 使用默认平台和镜像名
#   PLATFORM=linux/arm64 ./build-and-push.sh  覆盖平台
#   IMAGE=my-registry/app:v1 ./build-and-push.sh  覆盖镜像名
#
# 前提:
#   - 已安装 Docker Desktop 且 buildx 可用
#   - docker buildx inspect   确认 builder 存在
#   - docker login 已登录到目标 registry
# ============================================================

set -e

# ─── 可覆盖的变量 ──────────────────────────────────────────────
PLATFORM="${PLATFORM:-linux/amd64}"
IMAGE="${IMAGE:-registry.cn-zhangjiakou.aliyuncs.com/myelixir/tcm-edu:latest}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC}  $1"; }
ok()    { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ─── 前置检查 ──────────────────────────────────────────────────
command -v docker >/dev/null 2>&1 || err "请先安装 Docker"

if ! docker buildx version >/dev/null 2>&1; then
    err "docker buildx 不可用，请升级 Docker Desktop"
fi

# 确保 buildx builder 存在
if ! docker buildx inspect default >/dev/null 2>&1; then
    info "创建 buildx builder ..."
    docker buildx create --name default --use || true
fi

# ─── 显示构建信息 ──────────────────────────────────────────────
echo ""
info "============================================"
info " 平台:   ${PLATFORM}"
info " 镜像:   ${IMAGE}"
info " 本机:   $(uname -m)"
info "============================================"
echo ""

# ─── 构建 ──────────────────────────────────────────────────────
START=$(date +%s)

info "开始构建镜像 (${PLATFORM}) ..."
docker buildx build \
    --platform "${PLATFORM}" \
    -t "${IMAGE}" \
    --load \
    .

ELAPSED=$(($(date +%s) - START))
ok "构建完成 (${ELAPSED}s)"

# ─── 展示本地镜像 ──────────────────────────────────────────────
echo ""
docker images "${IMAGE}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"

# ─── 推送 ──────────────────────────────────────────────────────
echo ""
info "推送镜像到仓库 ..."
START=$(date +%s)

docker push "${IMAGE}"

ELAPSED=$(($(date +%s) - START))
ok "推送完成 (${ELAPSED}s)"

echo ""
ok "全部完成 → ${IMAGE}"
