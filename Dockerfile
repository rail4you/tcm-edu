# Built locally via docker buildx --platform linux/amd64. See build-and-push.sh.
#
# https://hub.docker.com/r/hexpm/elixir/tags?name=1.18.4-erlang-26
# https://hub.docker.com/_/debian/tags?name=trixie-20260610-slim
#
ARG BUILDER_IMAGE="docker.io/hexpm/elixir:1.18.4-erlang-26.2.5.21-debian-trixie-20260610"
ARG RUNNER_IMAGE="docker.io/debian:trixie-20260610-slim"

# ─── Stage 1: Frontend (Next.js → static export) ──────────────────────────
FROM docker.io/node:22-bookworm-slim AS frontend
ENV PNPM_HOME=/pnpm
ENV PATH=$PNPM_HOME:$PATH
RUN corepack enable && corepack prepare pnpm@9 --activate

WORKDIR /build/frontend

COPY frontend/package.json frontend/pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile --ignore-scripts

COPY frontend/ ./
ENV NODE_ENV=production
RUN pnpm build

# ─── Stage 2: Elixir builder (compile + release) ──────────────────────────
FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git \
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

# Copy Next.js static export into priv/app
COPY --from=frontend /build/frontend/out ./priv/app

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
