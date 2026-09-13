# @tcm-edu/web — 统一前端应用

单 Next.js 应用承载学生 / 教师 / 管理三端，按 URL 路径分流。参考 kg-edu 单端口模式。

## 目录约定

```
apps/web/
├── app/
│   ├── layout.tsx                # 根 layout：html/body/AuthProvider/全局样式
│   ├── globals.css               # Tailwind v4 学生端主题（cinnabar/rice/bamboo/ink）
│   ├── login/page.tsx            # 统一登录：三 Tab（学员 / 教师 / 管理）
│   ├── (student)/                # 学生路由组，路径为根 /、/courses、/learn、/my-learning、/posts、/chat
│   │   ├── layout.tsx            # Navbar + Footer + ToastProvider；非学生登录态跳走
│   │   ├── page.tsx              # 首页
│   │   ├── courses/page.tsx
│   │   ├── course/{page,detail-client}.tsx
│   │   ├── learn/page.tsx
│   │   ├── my-learning/page.tsx
│   │   ├── posts/{page,new/page}.tsx
│   │   └── chat/{page,streaming-markdown}.tsx
│   ├── (admin)/
│   │   └── admin/                # /admin/* 管理端（Antd + ProLayout，超管 + 租户管理员）
│   │       ├── layout.tsx        # AntdRegistry + ConfigProvider + 路由守卫
│   │       ├── page.tsx          # 工作台
│   │       ├── tenants/page.tsx
│   │       └── users/page.tsx
│   └── (teacher)/
│       └── teacher/              # /teacher/* 教师端（Antd + ProLayout）
│           ├── layout.tsx
│           ├── page.tsx          # 工作台
│           ├── courses/{page,new/page,[id]/edit/page}.tsx
│           └── students/page.tsx
├── components/                   # 学生端自研组件（Tailwind，不混 Antd）
│   ├── navbar.tsx
│   ├── footer.tsx
│   ├── hero-banner.tsx
│   ├── category-grid.tsx
│   ├── course-card.tsx
│   ├── teacher-card.tsx
│   ├── stats-bar.tsx
│   ├── learning-path.tsx
│   ├── enroll-button.tsx
│   ├── skeletons.tsx
│   └── toast.tsx
├── lib/
│   ├── auth/
│   │   ├── context.tsx           # 统一 AuthProvider（4 种 role）
│   │   ├── guard.tsx             # useRequireAuth({ allow }) 路由守卫
│   │   ├── compat.tsx            # 学生端 useAuth 兼容层（保留旧 API）
│   │   ├── types.ts              # Role / Session / ROLE_HOME
│   │   └── index.ts              # barrel 导出
│   ├── errors.ts                 # 学生端 RPC 错误处理
│   └── public-cache.ts           # 学生端公开查询缓存
├── next.config.mjs               # rewrites /api/* → :4011；prod basePath=/app
├── postcss.config.mjs
├── tsconfig.json
├── package.json                  # dev: :3000
└── …
```

## 启动

```bash
pnpm dev                # http://localhost:3000
```

后端 Phoenix 需单独启动在 `:4011`（项目根目录 `mix phx.server`）。

## 三端分流原理

| 端 | URL | 入口 layout | 登录后跳转 |
|---|---|---|---|
| 学生 | `/`, `/courses`, `/learn`, `/posts`… | `app/(student)/layout.tsx` | `/` |
| 管理 | `/admin`, `/admin/users`… | `app/(admin)/admin/layout.tsx` | `/admin` |
| 教师 | `/teacher`, `/teacher/courses`… | `app/(teacher)/teacher/layout.tsx` | `/teacher` |

**角色互审**：非本端角色进入会自动跳到自己的门户（在 layout 里 `useEffect` 判断）。三端共享同一份 session（`localStorage.tcm_session` + `localStorage.auth_token`），跨端零摩擦。

## 登录端点

| Tab | API | 角色返回 |
|---|---|---|
| 学员 | `POST /api/auth/user/password/sign_in` 或 `/register` | `student` |
| 教师 | `POST /api/auth/user/password/sign_in` | `teacher` / `tenant_admin` |
| 管理 | `POST /api/auth/super_admin_sign_in` | `super_admin` |

`useAuth()`（`lib/auth/context.tsx`）对外提供 `signInTenantUser` / `signInSuperAdmin` / `registerStudent` / `signOut`，登录页根据 Tab 选择对应方法，登录后用 `ROLE_HOME[role]` 跳到对应门户。

## Antd + Tailwind 共存

- Antd（管理 / 教师）：CSS-in-JS + `AntdRegistry` + `ConfigProvider`；在 `app/(admin)/admin/layout.tsx` 和 `app/(teacher)/teacher/layout.tsx` 各自包裹，作用域隔离
- Tailwind v4（学生）：`app/(student)/layout.tsx` 用自研 `@theme` token（cinnabar 朱红 / rice 米黄 / bamboo 竹青 / ink 墨色）
- 根 `app/layout.tsx` 只放 AuthProvider，不引入任何样式框架，保证两套互不干扰

## RPC 客户端

后端改了 resource / action 后：

```bash
mix ash_typescript.codegen
```

输出到 `packages/rpc-client/src/ash_rpc.ts`。统一应用通过 `@tcm-edu/rpc-client` workspace 包导入。

## 生产部署

- `pnpm build` → `apps/web/out/`
- Next.js 配置 `output: "export"` + `basePath: "/app"`（仅 prod），所有路径都带 `/app/` 前缀
- Dockerfile 把 `apps/web/out/*` 拷到 Phoenix 的 `priv/app/`
- Phoenix `FallbackController.app/2` 把 `priv/app/<path>` 挂在 `:4011/app/*`

所以生产 URL 是 `http://host/app/`、`http://host/app/admin`、`http://host/app/teacher` 等。

## 添加新页面

| 想加到 | 操作 |
|---|---|
| 学生端 | 在 `app/(student)/xxx/page.tsx` 加文件，URL 自动 = `/xxx` |
| 管理端 | 在 `app/(admin)/admin/xxx/page.tsx` 加文件，URL = `/admin/xxx` |
| 教师端 | 在 `app/(teacher)/teacher/xxx/page.tsx` 加文件，URL = `/teacher/xxx` |

跨端守卫已在 layout 里（`useRequireAuth({ allow: [...] })`），无需在每个页面再写。

## 清理历史

旧 `apps/student` / `apps/admin` / `apps/teacher` 三套独立 Next.js 应用（端口 3001/3002/3003）的代码已全部合并到此应用。清理时直接删除旧目录即可，不影响新应用。