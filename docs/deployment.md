# tcm-edu 部署指南

本文档整合 tcm-edu 从本地构建到生产部署的完整流程。应用为 **纯 Phoenix LiveView**
单应用（无独立前端），通过 Docker 镜像部署到单台服务器，nginx 反代对外服务。

---

## 1. 架构总览

```
浏览器
  │  http://111.229.72.15/            (公网只开放 80/443)
  ▼
服务器 nginx (:80)  ──proxy_pass──▶  Phoenix 容器 (127.0.0.1:4000)
  │                                   ├─ LiveView 页面（学生/教师/管理/课程）
  │                                   ├─ AI 功能（Jido agent + Oban 后台任务）
  │                                   └─ Ash API（认证、题库、存储等）
  ▼
PostgreSQL 容器 (tcm_edu 库)
  ├─ public schema     组织/超管/审计/API Key 配置
  └─ tenant_* schema   users/courses/quiz/chat 等租户数据
```

关键点：

- **容器端口固定 `127.0.0.1:4000`**，公网不暴露 4000，全部由宿主 nginx 反代。
- **LiveView 依赖 WebSocket**（`/live/websocket`），nginx 必须转发 `Upgrade` / `Connection`
  升级头（详见 §6）。
- **多租户迁移**分两处：`priv/repo/migrations`（public）+ `priv/repo/tenant_migrations`
  （每个 `tenant_*` schema）。release 容器里跑迁移用 `bin/migrate`（**没有 mix**）。

---

## 2. 服务器与目录

| 项 | 值 |
|---|---|
| 服务器 | `111.229.72.15` |
| SSH 别名 | `tcm-edu`（见 `~/.ssh/config`：`HostName 111.229.72.15 / User ubuntu`） |
| 远程目录 | `~/tcm-edu/` |
| 公网入口 | `http://111.229.72.15/` |
| 镜像仓库 | `registry.cn-zhangjiakou.aliyuncs.com/myelixir/tcm-edu:latest` |
| 运行网络 | `knowledgehub_abp-network`（与 postgres 容器同网） |

远程目录结构：

```
~/tcm-edu/
├── docker-compose.yml    # 服务编排（镜像/端口/环境变量）
├── .env                  # 生产密钥与连接配置（勿提交 git）
├── .env.example          # 模板
└── deploy.sh             # 远程服务管理（up/down/restart/logs/status/migrate）
```

---

## 3. 环境变量（.env）

`etc/docker/.env.example` 是模板，复制为 `.env` 并按需修改：

```bash
IMAGE=registry.cn-zhangjiakou.aliyuncs.com/myelixir/tcm-edu:latest
PUBLIC_URL=http://111.229.72.15
SECRET_KEY_BASE=<openssl rand -base64 64 生成>
TOKEN_SIGNING_SECRET=<openssl rand -base64 64 生成>
PHX_HOST=111.229.72.15          # 对外主机名，check_origin 用它匹配浏览器 Origin
DATABASE_URL=postgres://postgres:****@postgres:5432/tcm_edu
POOL_SIZE=10
TZ=Asia/Shanghai

# 文件存储（阿里云 OSS，AshStorage 上传必需）
OSS_ACCESS_KEY_ID=<阿里云 RAM AccessKey ID>
OSS_ACCESS_KEY_SECRET=<阿里云 RAM AccessKey Secret>
OSS_BUCKET=xingningshu              # 可选，默认 xingningshu
OSS_ENDPOINT=oss-cn-beijing.aliyuncs.com  # 可选
OSS_REGION=cn-beijing               # 可选
```

> ⚠️ `PHX_HOST` 是「公网访问主机名」，**不是**容器绑定 IP（`0.0.0.0`）。
> 若填 `0.0.0.0`，LiveView WebSocket 会因 `check_origin` 不匹配被拒（403）。
>
> ⚠️ **OSS 凭证必填**：课程封面 / AI 图片等所有上传都走 OSS。缺
> `OSS_ACCESS_KEY_ID` / `OSS_ACCESS_KEY_SECRET` 时上传会 raise
> `OSS_ACCESS_KEY_SECRET 未配置`（表现为「预览可见但提交后没保存」）。
> 在阿里云 RAM 创建子账号并授权 OSS 读写，把 key 填进 `.env`；`deploy.sh`
> 会把 `OSS_*` 变量注入容器。

---

## 4. 部署流程

完整一键部署（构建 + 推送 + 同步 + 远程拉取重启 + 迁移）：

```bash
./deploy.sh                 # 全流程
```

分步执行：

| 命令 | 作用 |
|---|---|
| `./deploy.sh build` | 本地 Mac 用 buildx 交叉构建 `linux/amd64` 镜像并推送到仓库 |
| `./deploy.sh remote` | 同步 `etc/docker/{docker-compose.yml,.env.example,deploy.sh}` 到远程 + 远程拉镜像重启容器 |
| `./deploy.sh migrate` | 远程在容器内跑 `bin/migrate`（public + 默认租户 + 所有租户迁移） |
| `./deploy.sh status` | 查看远程容器与镜像状态 |
| `./deploy.sh logs` | 查看远程容器日志 |

覆盖变量：

```bash
PLATFORM=linux/amd64 ./deploy.sh build          # 平台
IMAGE=my-registry/app:v1 ./deploy.sh            # 镜像名
REMOTE_HOST=tcm-edu REMOTE_DIR=~/tcm-edu ./deploy.sh
```

### 构建流程细节（`./deploy.sh build`）

1. `docker buildx build --platform linux/amd64 -t $IMAGE --load .`
   - Dockerfile 三段式：Elixir builder（编译 + `mix release`）→ 精简运行镜像
   - 产物是 release（无 Mix），镜像含 `bin/server` / `bin/migrate`
2. `docker images $IMAGE` 展示镜像大小
3. `docker push $IMAGE`

### rustler / NIF（`extractous_ex` 文档解析）构建说明

知识库文档解析用 `extractous_ex`（Rustler NIF，基于 Apache Tika）。构建与运行要点：

- **默认走预编译二进制**：`rustler_precompiled` 在编译时按目标平台从
  GitHub Release 下载 `libextractousex_native-<ver>-nif-<otp>-<target>.so.tar.gz`
  并解压到 `priv/native`。**要求编译环境能访问 github.com**；产物随镜像打包，
  运行阶段不再联网。
- **平台**：macOS (arm64/x64)、Linux (arm64/x64)、Windows (x64) 均有预编译包；
  本仓库 Docker 目标 `linux/amd64` 受支持。
- **下载失败 / 需要本地编译时**，二选一：
  - `EXTRACTOUS_EX_BUILD=1 mix deps.compile extractous_ex` —— 强制本地编译，
    需要 Dockerfile builder 里安装 Rust 工具链（`curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`）
    与 `cargo`、`libclang` 等（当前 Dockerfile **未**装 Rust）。
  - 或在 `config/config.exs` 设 `config :rustler_precompiled, :force_build, extractous_ex: true`
    （同样需要 Rust 工具链）。
- **GitHub 不可达（如阿里云/内网构建）**：预编译下载会失败。缓解：
  - 设置 `RUSTLER_PRECOMPILED_BASE_URL=https://<自托管>/...` 指向内网镜像，或
  - 本机 `buildx` 构建前先 `mix deps.compile extractous_ex` 让缓存命中
    （缓存目录 `~/.cache/rustler_precompiled`），再复制进构建上下文，或
  - 在本地预编译后把 `priv/native` 打进镜像（保持与目标 `linux/amd64` 一致）。
- **NIF 校验**：部署后 `docker exec tcm-edu ls /app/lib/tcm_edu-<ver>/priv/native/`
  应能看到 `libextractousex_native-*.so`；否则上传文档解析会报 NIF 加载失败。

### 远程部署细节（`./deploy.sh remote`）

1. 同步部署文件到 `~/tcm-edu/`
2. `.env` 不存在则从 `.env.example` 复制（需手动填密钥）
3. `docker pull $IMAGE` 拉最新镜像
4. `docker rm -f tcm-edu` 停旧容器
5. `docker run -d` 启动新容器（`127.0.0.1:4000`、`--network knowledgehub_abp-network`、
   注入全部环境变量）
6. `docker image prune -f` 清理旧镜像

> 本地开发与部署：本机开发用 `mix phx.server`；`./restart.sh` / `bin/herdr-services.sh`
> 是本地 dev 服务管理脚本（Phoenix only，前端已移除）。

---

## 5. 数据库迁移

**release 容器里没有 mix**，迁移一律用 `bin/migrate`（由 `mix phx.gen.release`
生成，底层调用 `TcmEdu.Release.migrate`）：

```bash
# 远程（deploy.sh 已封装）
./deploy.sh migrate

# 等效手动命令（容器内）
docker exec -it tcm-edu /app/bin/migrate
```

`bin/migrate` 依次执行：

1. **public 迁移**：`priv/repo/migrations`（organizations / super_admins / audit_logs / tokens…）
2. **默认租户**：`tenant_default` 不存在则自动创建 schema + 租户
3. **租户迁移**：对所有 `tenant_*` schema 跑 `priv/repo/tenant_migrations`

本地开发用 mix 迁移：

```bash
mix tcm_edu.migrate           # public + 默认租户 + 所有租户
mix tcm_edu.migrate --tenants # 只跑租户迁移
mix ash.codegen add_xxx       # 资源改动后生成迁移
```

> 迁移目录路径已改为 `Application.app_dir/2` 解析，dev 与 release 均正确；
> 不要用 psql 手动建表改表，一律走迁移命令。

---

## 6. nginx 反代（80 端口）

配置文件：`etc/nginx/tcm-edu.conf`（已部署到 `/etc/nginx/sites-available/`）。

安装/更新：

```bash
scp etc/nginx/tcm-edu.conf tcm-edu:/tmp/
ssh tcm-edu 'sudo cp /tmp/tcm-edu.conf /etc/nginx/sites-available/tcm-edu.conf \
  && sudo nginx -t && sudo systemctl reload nginx'
```

要点：

- `listen 80 default_server`，`server_name _`
- `client_max_body_size 100m`（课程封面上传需要）
- **WebSocket 升级头**（LiveView 必需）：

```nginx
location / {
    proxy_pass http://127.0.0.1:4000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 120s;
}
```

HTTPS(443) 目前未启用；需要时用 certbot 签证书后按 `tcm-edu.conf` 内注释启用。

---

## 7. 端口与安全

| 端口 | 绑定 | 说明 |
|---|---|---|
| 80 | `0.0.0.0:80` (nginx) | 公网 HTTP 入口 |
| 443 | 未启用 | 可选 HTTPS |
| 4000 | `127.0.0.1:4000` (容器) | 仅本机回环，仅 nginx 可访问 |

---

## 8. 验证部署

```bash
# 应用可达
curl -s -o /dev/null -w "%{http_code}\n" http://111.229.72.15/          # 200

# WebSocket 握手（LiveView 依赖）
curl -s -i --max-time 8 \
  -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  http://111.229.72.15/live/websocket | head -1                          # 101 Switching Protocols

# 容器健康
ssh tcm-edu 'docker ps --filter name=tcm-edu'

# 镜像大小 / 日志
./deploy.sh status
./deploy.sh logs
```

---

## 9. 常见问题

| 症状 | 原因 / 排查 |
|---|---|
| 浏览器 `WebSocket connection to .../live/websocket ... failed` | nginx 缺 `Upgrade`/`Connection` 头（§6）；或 `PHX_HOST` 与浏览器 Origin 不一致导致 `check_origin` 403（§3）。容器日志会打 `Could not check origin for Phoenix.Socket transport`。 |
| `bin/migrate` 显示 "Migrations already up" 但表没建 | 迁移目录路径问题：release 里必须能解析到 `/app/lib/tcm_edu-<ver>/priv/repo/tenant_migrations`（已修复为 `Application.app_dir/2`）。 |
| 容器启动报 `port 4000 already in use` | 上一个容器未停，先 `docker rm -f tcm-edu`。 |
| 登录失败重定向回 `/login` | 密码不对（用户被外部创建、非 seed 默认密码）。可重置密码哈希。 |
| 上传封面能看到预览，但提交后没保存 / 容器日志 `OSS_ACCESS_KEY_SECRET 未配置` | 容器缺 OSS 凭证：检查 `.env` 是否有 `OSS_ACCESS_KEY_ID`/`OSS_ACCESS_KEY_SECRET` 且 `deploy.sh` 已注入（`docker exec tcm-edu env | grep OSS_`）。§3。 |
| 知识库上传文档解析报 NIF 加载失败 / `failed to load NIF library` | release 缺 `extractous_ex` 的预编译 `.so`：`docker exec tcm-edu ls /app/lib/tcm_edu-<ver>/priv/native/` 检查；构建时 GitHub 不可达或未走预编译，见「rustler / NIF 构建说明」。 |
| 公网直连 4000 不可达 | 正常：4000 仅绑定回环，nginx 反代 80。 |

---

## 10. 生产账户（seed 创建，密码默认 `password123`）

| 身份 | 邮箱 | 备注 |
|---|---|---|
| 超管（管理端） | `admin-lt@example.com` | `public.super_admins` |
| 教师 | `real-teacher@example.com` | 若登录失败多为密码被改，见 §9 |

seed 脚本：

```bash
mix tcm_edu.seed_super_admin     # 超管
mix tcm_edu.seed_courses         # 教师 + 示例课程（创建 seed-teacher@example.com）
```