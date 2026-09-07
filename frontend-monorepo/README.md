# frontend-monorepo

TCM-Edu 前端 monorepo（pnpm workspaces）。三个应用共享同一个 RPC 客户端。

## 目录

```
frontend-monorepo/
├── apps/
│   ├── student/   # 学生端（Next.js + Tailwind + 自定义组件） :3001
│   ├── admin/     # 管理端（Next.js + Antd：超管 / 租户管理员） :3002
│   └── teacher/   # 教师端（Phase 5）
├── packages/
│   ├── rpc-client/  # `mix ash_typescript.codegen` 输出 + 共享 auth hooks
│   ├── ui-admin/    # 管理/教师端共享组件（Phase 5 教师端落地时再沉淀）
│   └── config/      # 共享 tsconfig.base.json
└── pnpm-workspace.yaml
```

## 端口

| 应用 | 端口 | 说明 |
|------|------|------|
| student | 3001 | `:3000` 被 OrbStack/Gotenberg 占用，故用 3001 |
| admin | 3002 | 管理端 |
| teacher | 3003 | Phase 5 |

后端 Phoenix 固定 `:4011`；各应用的 `/api/*` 通过 `rewrites()` 代理到 `:4011`。

## 常用命令（在 `frontend-monorepo/` 下执行）

```bash
pnpm install                          # 安装全部 workspace 依赖
pnpm --filter @tcm-edu/student dev    # 学生端 :3001
pnpm --filter @tcm-edu/admin dev      # 管理端 :3002
pnpm --filter @tcm-edu/teacher dev    # 教师端（Phase 5）
pnpm -r typecheck                      # 全部类型检查
pnpm -r lint                           # 全部 lint（注：存量红灯，见根 AGENTS 说明）
```

> 无 pnpm 时：`corepack enable` 即可（`packageManager: pnpm@11.3.0`）。
> `pnpm install` 需加 `--ignore-scripts`（`neverBuiltDependencies` 已声明 sharp/unrs-resolver 跳过，原因见 `pnpm-workspace.yaml` 注释）。

## RPC 客户端更新流程

后端改了 resource / action 后：

```bash
# 在项目根执行（不是 frontend-monorepo）
mix ash_typescript.codegen   # 输出到 packages/rpc-client/src/
```

各 app 通过 `@tcm-edu/rpc-client` 导入，**不要**各自复制 generated 文件。

## 登录入口

- 管理端 `/login`：两个 Tab —— 超管（`POST /api/auth/super_admin_sign_in`）/ 租户管理员（`POST /api/auth/user/password/sign_in`，body 形如 `{"user": {"email", "password"}}`）。
- Token 存 `localStorage.auth_token`（与 `rpc-client` 的 `beforeRequest` hook 共用 key），session 存 `localStorage.tcm_admin_session`。
