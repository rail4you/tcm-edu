# frontend-monorepo

TCM-Edu 前端 monorepo（pnpm workspaces）。**单一 Next.js 应用**承载学生 / 教师 / 管理三个端，通过 URL 路径分流，参考 [kg-edu](https://github.com/...) 的单端口模式。

## 目录

```
frontend-monorepo/
├── apps/
│   └── web/                 # 统一 Next.js 应用（dev :3000，prod 静态导出 → priv/app/）
└── packages/
    ├── rpc-client/          # `mix ash_typescript.codegen` 输出 + 共享 auth hooks
    └── config/              # 共享 tsconfig.base.json
```

## 单端口路由

| URL                  | 端   | 说明                         |
| -------------------- | ---- | ---------------------------- |
| `/`                  | 学生 | 公开站首页（hero/courses/...）|
| `/courses` `/course` `/learn` `/my-learning` `/posts` `/chat` | 学生 | 学生端路由 |
| `/login`             | 登录 | 三 Tab：学员 / 教师 / 管理   |
| `/admin` `/admin/*`  | 管理 | 超管 + 租户管理员（Antd）    |
| `/teacher` `/teacher/*` | 教师 | 教师 + 机构管理员（Antd）    |

dev 模式下三端共享 `http://localhost:3000`，仅 URL 路径不同。后端 Phoenix 固定 `:4011`，`/api/*` 通过 `rewrites()` 代理。

## 启动

```bash
pnpm install                          # 安装全部 workspace 依赖
pnpm dev                              # 启动统一前端 :3000
```

后端单独启动（项目根目录）：

```bash
mix phx.server                        # → :4011
```

## 登录入口

`/login` 页三个 Tab：

- **学员** — 学生邮箱 + 密码（首次可注册）；登录后跳 `/`
- **教师** — 教师/机构管理员邮箱 + 密码；登录后跳 `/teacher`
- **管理** — 超管专用入口（`POST /api/auth/super_admin_sign_in`）；登录后跳 `/admin`

登录后 token 写 `localStorage.auth_token`，session 写 `localStorage.tcm_session`，统一由 `lib/auth/context.tsx` 管理。三端共用同一 session，跨端调试零摩擦。

## RPC 客户端更新

后端改了 resource / action 后：

```bash
mix ash_typescript.codegen   # 输出到 packages/rpc-client/src/
```

`apps/web` 通过 `@tcm-edu/rpc-client` 导入，**不要**自己复制 generated 文件。

## 生产构建

```bash
pnpm build                            # 输出到 apps/web/out/
```

Next.js 配置 `basePath: "/app"`（仅 production），所以 `out/` 下的所有路径都带 `/app/` 前缀。Dockerfile 把 `apps/web/out/*` 拷到 `priv/app/`，由 Phoenix `FallbackController.app/2` 在 `:4011/app/*` 提供。

## 旧 app 目录

迁移前 `apps/{student,admin,teacher}` 三套独立 Next.js 应用（端口 3001/3002/3003）已合并到 `apps/web/`。如需清理，删除旧目录即可，不影响新应用。

> 无 pnpm 时：`corepack enable`（`packageManager: pnpm@11.3.0`）。
> `pnpm install` 需加 `--ignore-scripts`（`neverBuiltDependencies` 已声明 sharp/unrs-resolver 跳过）。