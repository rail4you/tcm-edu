# Built locally via docker buildx --platform linux/amd64. See build-and-push.sh.
#
# https://hub.docker.com/r/hexpm/elixir/tags?name=1.18.4-erlang-26
# https://hub.docker.com/_/debian/tags?name=trixie-20260610-slim
#
ARG BUILDER_IMAGE="docker.io/hexpm/elixir:1.18.4-erlang-26.2.5.21-debian-trixie-20260610"
ARG RUNNER_IMAGE="docker.io/debian:trixie-20260610-slim"

# ─── Stage 1: Frontend (pnpm monorepo → Next.js static export) ───────────
# 单一 Next.js 应用 @tcm-edu/web，承载学生/教师/管理三端，basePath=/app。
FROM docker.io/node:22-bookworm-slim AS frontend
ENV PNPM_HOME=/pnpm
ENV PATH=$PNPM_HOME:$PATH
RUN corepack enable && corepack prepare pnpm@11 --activate

WORKDIR /build/frontend-monorepo

# 先拷 workspace 顶层 manifest + packages 元数据，让 pnpm install 能识别 workspace 拓扑
COPY frontend-monorepo/package.json frontend-monorepo/pnpm-workspace.yaml frontend-monorepo/pnpm-lock.yaml* ./
COPY frontend-monorepo/packages/ ./packages/
COPY frontend-monorepo/apps/web/package.json ./apps/web/

RUN pnpm install --frozen-lockfile --ignore-scripts

# 拷 web app 源码（packages/rpc-client 的 generated 文件随源码一起 COPY，git 里已 check-in）
COPY frontend-monorepo/apps/web/ ./apps/web/

ENV NODE_ENV=production
RUN pnpm --filter @tcm-edu/web build

# ─── Stage 2: Elixir builder (compile + release) ──────────────────────────
FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git curl \
  && rm -rf /var/lib/apt/lists/*

# Node.js for the Phoenix assets pipeline (Tailwind v4 + daisyUI + esbuild).
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force \
  && mix local.rebar --force

# +JMsingle true: 强制单线程 JIT，避免 QEMU/Rosetta 模拟下
# Erlang VM 的内存竞态导致 binary_to_term 损坏（ymlr/stream_data 等）。
ENV MIX_ENV="prod"
ENV ERL_AFLAGS="+JMsingle true"

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV && mix deps.compile

COPY config/ config/
COPY priv priv
COPY lib lib

# Build Phoenix LiveView assets (assets/ → priv/static/assets/)
COPY assets/package.json assets/package-lock.json* assets/
COPY assets/css/ assets/css/
COPY assets/js/ assets/js/
COPY assets/vendor/ assets/vendor/
RUN npm --prefix assets ci && npm --prefix assets run build

# Copy Next.js static export into priv/app
COPY --from=frontend /build/frontend-monorepo/apps/web/out ./priv/app

RUN mix compile

COPY rel rel
RUN mix release

# ─── Stage 3: Runtime ─────────────────────────────────────────────────────
FROM ${RUNNER_IMAGE} AS final

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

ENV MIX_ENV="prod"

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/tcm_edu ./

USER nobody

EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://127.0.0.1:4000/ || exit 1

CMD ["/app/bin/server"]
