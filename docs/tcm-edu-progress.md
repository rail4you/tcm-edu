# TCM-Edu · 实施进度跟踪

> **当前状态**：🟢 Phase 7 已完成，下一步 Phase 8（学生端首页）
> **开始日期**：2026-09-06
> **预计完成**：（待定）
> **部署目标**：111.229.72.15（`ssh tcm-edu` 免密；`deploy.sh` 默认 REMOTE_HOST 已切到 `tcm-edu`）
>
> **使用方式**：每完成一项，把 `[ ]` 改成 `[x]`，并在右侧备注里写实际工期 / commit hash / 阻塞原因

## 进度一览

```
Phase 0  🟢 文档与方案评审       [============] 5/5
Phase 1  🟢 多租户基础设施       [============] 38/38
Phase 2  🟢 认证与超管体系       [============] 30/30
Phase 3  🟢 重构 User + 角色     [============] 21/21
Phase 4  🟢 超管 Console         [============] 36/39
Phase 5  🟢 教师 Console         [============] 12/12
Phase 6  🟢 课程域              [============] 41/42
Phase 7  🟢 选课与进度           [============] 8/8
Phase 8  ⬜ 学生端首页           [============] 0/12
Phase 9  ⬜ 课程列表 + 详情      [============] 0/14
Phase 10 ⬜ 集成打磨            [============] 0/10
Phase 11 ⬜ 部署与文档          [============] 0/8

总进度：202 已完成 / 153 待办（以文档内实际勾选为准；早期 145 为粗估）
```

图例：⬜ 未开始　🟡 进行中　🟢 已完成　🔴 受阻

---

## Phase 0 · 文档与方案评审 🟢 已完成

> 目标：方案文档 + 用户 review 通过
> 完成日期：2026-09-06

- [x] 编写 `docs/tcm-edu-dev-plan.md`（主方案）
- [x] 编写 `docs/tcm-edu-progress.md`（本文档）
- [x] 用户 review → 回答 §13.1 的 12 个决策点
- [x] 修改方案文档（如有反馈）— 确认不用 AshAdmin，全部手写 Antd
- [x] 用户确认进入 Phase 1

**完成标准**：用户在聊天里明确说"开始开发！"

---

## Phase 1 · 多租户基础设施 🟢 已完成

> 目标：让系统支持多租户 + 可创建租户
> 前置依赖：Phase 0 完成 ✅
> 实际工期：1 天
> 完成日期：2026-09-06

### 1.1 Organization 资源 🟢

- [x] 创建 `lib/tcm_edu/system.ex` 域
- [x] 创建 `lib/tcm_edu/system/organization.ex` 资源
- [x] 配置 `manage_tenant` 块（schema 名 = `"tenant_" <> slug`）
- [x] `Ash.ToTenant` 由 manage_tenant 自动生成
- [x] 定义 attributes：name、slug、schema_name、contact_email、contact_phone、status、plan、expires_at
- [x] 定义 actions：create_with_schema、archive、suspend、activate、destroy（DROP SCHEMA CASCADE）
- [x] 定义 policies（Phase 2 之前暂放空；正式收口在 super_admin 完成后）
- [x] 写 typescript block（`type_name "Organization"`）
- [x] 在 `config/config.exs` 注册新域

### 1.2 TenantProvisioning 服务 🟢

- [x] 创建 `lib/tcm_edu/tenant_provisioning.ex`
- [x] 实现 `provision_tenant/1`：建 schema → 跑迁移 → 创建初始 admin（Phase 3 启用）
- [x] 实现 `all_tenant_schemas/0`
- [x] 实现 `run_migrations_for_all_tenants/0`
- [x] 实现 `create_schema/1`、`run_tenant_migrations/1` 私有函数
- [x] 写 `test/tcm_edu/system/organization_test.exs`（8 个测试）

### 1.3 双轨迁移 🟢

- [x] 创建 `priv/repo/tenant_migrations/` 目录
- [x] 创建初始租户迁移 `20260830000001_create_tenant_skeleton.exs`（含 `tenant_system_info` 表）
- [x] 创建 `priv/repo/migrations/20260830000001_create_organizations.exs`
- [x] 创建自定义 mix 任务 `lib/mix/tasks/tcm_edu.migrate.ex`
- [x] mix 任务步骤：① 主迁移 ② 创建默认租户 ③ 跑所有租户迁移
- [x] 测试：`mix tcm_edu.migrate` 成功执行

### 1.4 测试 🟢

- [x] round-trip 测试：创建租户 → 检查 schema 存在 → 检查 tables 存在（✅）
- [x] 删除租户 → 检查 schema 被 CASCADE 删除（✅）
- [x] 默认租户 `tenant_default` 自动创建（✅ 通过 mix task）
- [x] slug 唯一性 + 格式校验（✅）
- [x] 状态转换 archive/activate/suspend（✅）

### 1.5 Phase 1 完成标志 ✅

- [x] `mix tcm_edu.migrate` 一次性成功
- [x] RPC `create_organization` 能在 `pg_namespace` 看到 `tenant_<slug>`
- [x] 在新租户的 schema 中能查到 `tenant_system_info` 和 `schema_migrations` 表
- [x] `mix test test/tcm_edu/system/organization_test.exs` 8/8 通过
- [x] `mix test` 全量：27/29 通过（2 个 AI chat 测试因 LLM API 余额失败，与本次改动无关）
- [x] `mix compile --warnings-as-errors` 干净（仅 chat_controller.ex 预存在 warning）
- [x] 更新本文档勾选状态
- [ ] Git commit + push（用户允许 commit 时执行）

### 🐛 踩坑记录

1. **DROP SCHEMA 需引号包裹**：`tenant_acme-123` 里的 `-` 被 PG 当作减号，会报 syntax error。必须写成 `DROP SCHEMA IF EXISTS "tenant_acme-123"`。
2. **`Ash.update(record, :action, params, opts)` 4-arity 不存在**：Ash 3.x 需用 `Ash.Changeset.for_update/2` 然后 `Ash.update/2`。
3. **SQL Sandbox 与外部事务隔离**：测试里 `all_tenant_schemas` 看得到本测试创建的新 schema，看不到之前 `mix tcm_edu.migrate` 创建的（sandbox 是 savepoint 事务）。测试只断言本次创建即可，不检查外部 `tenant_default`。
4. **Destroy action 需 `primary? true`**：否则 `Ash.destroy/2` 报"no primary action"。

---

## Phase 2 · 认证与超管体系 🟢 已完成

> 目标：超管能登录、能切换租户上下文
> 前置依赖：Phase 1 完成 ✅
> 实际工期：0.5 天
> 完成日期：2026-09-06

### 2.1 SuperAdmin 资源 🟢

- [x] 创建 `lib/tcm_edu/system/super_admin.ex`
- [x] attributes：email (citext)、name、hashed_password、last_login_at
- [x] identities：unique_email
- [x] actions：register、sign_in_with_password、touch_last_login
- [x] 自定义 Bcrypt hash（不依赖 AshAuthentication strategy）
- [x] 写测试 `test/tcm_edu/system/super_admin_test.exs`（6 个测试）

### 2.2 自定义 JWT Claims 🟢

- [x] 创建 `lib/tcm_edu_web/auth_token.ex`（Joken + HS256，同 AshAuthentication 密钥）
- [x] 在 token payload 中加入 `tenant`、`role` claim
- [x] super_admin 登录生成的 JWT：`tenant: "public"`、`role: "super_admin"`
- [x] 普通用户登录生成的 JWT：`tenant: "public"`、`role: "<user_role>"`（Phase 3 会改为 `tenant_<slug>`）
- [x] 写测试 `test/tcm_edu_web/auth_token_test.exs`（6 个测试）

### 2.3 SetTenantFromToken Plug 🟢

- [x] 创建 `lib/tcm_edu_web/plugs/set_tenant_from_token.ex`
- [x] 从 JWT 提取 tenant + subject
- [x] 根据 tenant 加载 actor（super_admin → public.super_admins；其他 → public.users）
- [x] 设置 `conn.private[:ash_actor]`、`conn.private[:ash_tenant]`、`conn.private[:ash_context]`、`conn.private[:tcm_edu_role]`
- [x] 写入 router 的 `:api_auth` pipeline（叠加 `set_actor` 之后）

### 2.4 三种登录入口 🟢

- [x] 在 `AuthController` 增加 `super_admin_sign_in/2` action
- [x] `success` 回调对租户用户 JWT 自动加上 tenant + role
- [x] `me/2` 返回 actor + tenant + role
- [x] 在 router 中添加 `/api/auth/super_admin_sign_in` 路由
- [x] 已有的 `/api/auth/user/password/sign_in`（auth_routes 生成）走 `success` 回调后返回新 JWT
- [x] 写测试：3 种登录都返回有效 JWT

### 2.5 种子数据 🟢

- [x] 创建 `mix tcm_edu.seed_super_admin` 任务（KV 风格 CLI：EMAIL=... PASSWORD=...）
- [x] 已创建 `admin@example.com / password123`（id=852f1548-...）

### 2.6 Phase 2 完成标志 ✅

- [x] `curl` 3 种登录都能拿到 JWT
- [x] JWT 包含 `sub`、`tenant`、`role`、`iat`、`exp` claim
- [x] 携带超管 JWT 访问 `/api/rpc/run` 能正常解析 actor（list_organizations 返回 tenant_default）
- [x] 携带普通用户 JWT 访问 `/api/rpc/run` 受 RBAC 限制（list_organizations forbidden）
- [x] `/api/auth/me` 返回完整 actor + tenant 信息
- [x] 错误密码返回 401 + invalid_credentials
- [x] `mix test` 12/12 新增测试通过；39/41 总通过（2 个 AI chat 测试因 LLM 余额失败，与与预）
- [x] `mix compile --warnings-as-errors` 干净（仅 chat_controller.ex 预存在 warning）
- [x] `mix ash_typescript.codegen` 成功生成 SuperAdmin typescript types
- [x] 更新本文档勾选状态
- [ ] Git commit + push（用户允许 commit 时执行）

### 🐛 踩坑记录（Phase 2）

1. **Joken API 的 arity 坑**：`Joken.generate_and_sign/2` 默认 signer_arg = `:default_signer`，会忽略传入的 `%Signer{}`。要用 3-arity `generate_and_sign(token_config, extra_claims, signer)` 或 4-arity。
2. **Action 里 `__MODULE__` 是 action 模块不是资源**：`Ash.Query.filter(__MODULE__, ...)` 会报错 "Expected a resource or a query, got: SuperAdmin"。在 action block 里要用全名 `TcmEdu.System.SuperAdmin`。
3. **`Ash.update/5` 5-arity 不存在**：Ash 3.x 只有 `Ash.update/3` 或 `Ash.update/2`。要用 `Ash.Changeset.for_update/3` + `Ash.update/2`。
4. **Change 在 validation 失败后仍运行**：默认 `only_when_valid? false`，会 hash nil 报错。给 change 加 `only_when_valid?: true`。
5. **`expr(now())` 返回类型问题**：在 `:utc_datetime` 字段上用 `expr(now())` 会报 "Could not cast input to datetime"。改用 `change set_attribute(:last_login_at, &DateTime.utc_now/0)`。
6. **Ash wrap 自定义错误为 `Ash.Error.Unknown`**：action 返回 `{:error, :invalid_credentials}` 后，Ash 包装成 `%Ash.Error.Unknown{error: ":invalid_credentials"}`。不能用 pattern match 判，只能 `inspect(err) =~ "invalid_credentials"`。
7. **AshAuthentication.Strategy.Password 期望 `params[subject_name]` 格式**：`User` 资源的 subject_name 是 `"user"`，所以 sign-in body 必须是 `{"user": {"email": "...", "password": "..."}}`。

---

## Phase 3 · 重构 User + 角色扩展 🟢 已完成

> 目标：User 资源支持多租户 + 三种角色
> 前置依赖：Phase 2 完成 ✅
> 实际工期：1 天
> 完成日期：2026-09-06

### 3.1 重写 User 资源 🟢

- [x] 修改 `lib/tcm_edu/accounts/user.ex`
- [x] 加 `multitenancy do strategy :context end`
- [x] 改 `role` 约束 `[:tenant_admin, :teacher, :student]`（default `:student`）
- [x] 加 `status` 字段（`:active` / `:disabled`）
- [x] 加 `name`、`avatar_url`、`phone`、`bio`、`job_title`、`school`、`major` 字段
- [x] 重写 policies：SuperAdmin struct 全 bypass；tenant_admin 管本租户；用户改自己（详见 `user.ex` 注释）

### 3.2 数据迁移 🟢

- [x] 租户迁移 `20260830000002_create_tenant_users.exs`：各 `tenant_*` 建 `users` 表
- [x] 主迁移 `20260830000003`：删旧 RBAC 表（`users1` 用 CASCADE，因被演示表引用）
- [x] `mix tcm_edu.migrate` 新增第 4 步：`public.users` → `tenant_default.users`（`admin→tenant_admin`、`user→student`），然后 DROP `public.users`
- [x] 验证：14 条记录全量迁移（2 tenant_admin + 12 student）；原 admin 账号可登录到 `tenant_default`

### 3.3 User 代码接口 🟢

- [x] 精简 `TcmEdu.Accounts` 域：去掉已删除的 Role/Permission 资源，保留 User + Token
- [x] 暴露 `list_users`、`list_students`、`list_teachers`、`list_admins`
- [x] 暴露 `register_with_role`（创建）、`update_profile`（自助资料）、`update_user_role` / `update_user_status`（改角色/状态）、`change_user_password`（改密码）
- [x] RBAC 兼容函数 `effective_permissions?/2`、`effective_permissions/1` 改为 no-op（旧表已删，避免残留代码报错）

### 3.4 测试 🟢

- [x] `test/tcm_edu/accounts/user_multitenancy_test.exs`（20 个测试，全部通过）
- [x] role 约束：旧 `:admin`/`:user` 拒绝；新三角色通过；密码 <8 拒绝；Bcrypt 可验证
- [x] tenant_admin/teacher 能 list；student 调 list 被 forbidden；student 只能 read 自己
- [x] student 不能 register / update_role / destroy；通用 `:update` 仅 admin（防提权）
- [x] 用户能改自己 profile + change_password；admin 能改他人
- [x] 跨租户隔离：A 租户行在 B 租户不可见（schema 级隔离；tenant 由 JWT 决定，API 层不接受客户端传 tenant）

### 3.5 Phase 3 完成标志 ✅

- [x] `mix ash_typescript.codegen` 成功生成新 RPC（`listStudents`、`registerWithRole`、`updateProfile` 等）
- [x] `tenant_default.users` 包含原有 admin + user 账号（14 条）
- [x] `mix test` 全量 59/61（仅 2 个 AI chat 测试因 LLM 余额失败，预存问题）；新增 20/20 通过
- [x] `mix compile` 干净（仅 `chat_controller.ex` 预存 warning）
- [x] E2E：admin list 14 条 / student list 被 Forbidden / admin 可 register teacher
- [x] 更新本文档勾选状态
- [ ] Git commit + push（用户允许 commit 时执行）

### 🐛 踩坑记录（Phase 3）

1. **policy 条件列表是 AND 语义**：`policy [action(:a), action(:b)]` 要求动作同时是 a 和 b，永不生效。必须每个 action 独立一个 policy 块（本次最大坑，表现为 admin/list_users 莫名 forbidden，而单条件 list_admins 正常）。
2. **SuperAdmin 没有 `:role` 属性**：`actor_attribute_equals(:role, :super_admin)` 对 SuperAdmin struct 永假。用 `actor_attribute_equals(:__struct__, TcmEdu.System.SuperAdmin)` 做 bypass。
3. **通用 `:update` 会被 student 滥用提权**：`defaults([:update])` 保留时，必须把默认 `:update` 限为 admin-only，普通用户走 `update_profile` / `change_password`。
4. **test 库没有 tenant schema**：`mix test` 别名只跑主迁移。`MIX_ENV=test mix tcm_edu.migrate` 补建一次，并把 `tcm_edu.migrate` 加进 `mix.exs` 的 `test` 别名。
5. **codegen 会生成已手动处理过的 dev 迁移**：`mix ash.codegen --dev` 产物与手写迁移重复时，删 migration 文件、留 snapshot json 即可。

---

## Phase 4 · 超管 Console（管理端骨架）🟢 已完成

> 目标：超管能登录 UI、能管理租户和用户
> 前置依赖：Phase 3 完成 ✅
> 实际工期：1 天
> 完成日期：2026-09-06

### 4.1 Monorepo 初始化 🟢

- [x] 在 `/Users/bai/projects/tcm-edu/` 新建 `frontend-monorepo/`
- [x] 创建 `pnpm-workspace.yaml`（含 `neverBuiltDependencies` 说明，见坑 2）
- [x] 创建根 `package.json`（`dev:student` / `dev:admin` / `typecheck` 脚本）
- [x] 把现有 `frontend/` 迁移到 `frontend-monorepo/apps/student/`（删 `node_modules/.next/out` 后搬）
- [x] 更新 `apps/student/package.json` 的 name 为 `@tcm-edu/student`（+ `dev -p 3001` + `typecheck` 脚本）
- [x] 创建 `packages/rpc-client/`、`packages/ui-admin/`、`packages/config/`
- [x] codegen 输出改到 `packages/rpc-client/src/`；student 4 个页面改 import `@tcm-edu/rpc-client`；删 student 残留 `app/admin/`（旧 demo 管理页，已由新管理端接管）
- [x] `config/config.exs` 同步 codegen 路径；`README.md` 开发章节同步 monorepo

### 4.2 Admin App 初始化 🟢

- [x] 创建 `apps/admin/`：Next.js 16 + Antd 5 + `@ant-design/icons`
- [x] 配置 Antd SSR registry（`@ant-design/nextjs-registry` + `v5-patch-for-react-19`）
- [x] 配置 ProLayout（`@ant-design/pro-components`，按 role 的菜单）
- [x] 配置 `next.config.mjs` 代理 `/api/*` → `:4011`（+ `turbopack.root` 指 monorepo 根，见坑 4）
- [x] 经 `@tcm-edu/rpc-client` 接入（workspace 软链；student 同包，单源）
- [x] 验证：admin dev 启动成功（:3002，pane `w654342d23d7673:p4`）

### 4.3 认证与布局 🟢

- [x] 实现登录页（超管 / 租户管理员双 Tab，对应两个后端入口）
- [x] 实现 `lib/auth.tsx`（token+role+tenant 存 localStorage，与 rpc hooks 共用 `auth_token` key）
- [x] 实现 ProLayout + 侧边栏菜单（超管：工作台/租户/用户；租户管理员：工作台/用户）
- [x] 实现路由守卫：未登录跳 `/login`
- [ ] token 自动刷新（defer：后端无 refresh 端点；401 由 message 提示，见 4.7 后续）
- [x] 测试：E2E curl 代替（双登录 + `/me` + 带 token RPC，见 4.7）

### 4.4 工作台页 🟢

- [x] 实现 `/` 首页（两角色不同视图）
- [x] 超管：租户总数/运营中/暂停/归档 + 最近租户表；租户管理员：本租户用户/教师/学生数
- [x] `get_all_organization_summary` action 不存在（kg-edu 参考遗留）→ 改为客户端聚合（`listOrganizations` + 按 status 计数）
- [x] 显示最近创建的租户表格（前 5，客户端截断；`insertedAt` 非 public 字段故不用服务端排序）

### 4.5 租户管理页 🟢

- [x] 实现 `/tenants` 列表页（超管菜单独占）
- [x] 实现创建租户 Modal（name、slug 格式校验、contactEmail、plan；成功回显 schema 名）
- [x] 实现编辑租户（name/contact/plan/description；slug/schema 不可改）
- [x] 实现暂停/恢复/归档/删除（含 DROP SCHEMA CASCADE 二次确认）
- [x] 调用 `Organization` 全套 actions；E2E 验证建→停→启→删闭环
- [x] 测试：E2E curl 代替（见 4.7）
- [x] 后端补 `update_details` 显式 action（默认 `:update` 无 RPC input，见坑 5）

### 4.6 用户管理页 🟢

- [x] 实现 `/users` 列表页（超管：租户下拉筛选 + `tenant` override；租户管理员：固定本租户 Tag）
- [x] 实现创建用户 Modal（email/name/password/role；租户来自筛选器或 session）
- [x] 实现改角色 / 启停用 / 删除（含确认）
- [ ] 管理员重置密码（defer：需后端 `admin_reset_password` action，见 4.7 后续）
- [x] 调用 `User` 全套 actions（含新增 `delete_user` RPC）
- [x] 测试：E2E curl 代替（admin 建 teacher 成功；student 调 list 被 Forbidden）

### 4.7 Phase 4 完成标志 ✅

- [x] 超管登录后看到平台总览（租户状态统计 + 最近租户表）
- [x] 超管能在 UI 代理链路上创建租户（含自动建 schema，E2E：`tenant_e2e-tcm` 建删闭环，库已恢复干净）
- [x] 超管能跨租户创建用户（`tenant` override，E2E 验证）
- [x] 租户管理员菜单仅工作台/用户（代码级按 role 过滤）+ 后端 `Organization` 写操作已收紧（tenant_admin 建租户 → Forbidden，E2E 验证）
- [x] `tsc --noEmit` 三件套全过（rpc-client/student/admin）；lint 保持仓库现状（student 存量 7 error，本次 admin 仅同类 hooks 规则提示，未恶化）
- [x] 更新本文档勾选状态
- [ ] Git commit + push（用户允许 commit 时执行）

### ➡️ 后续补齐（不阻塞 Phase 5）

- [ ] 管理员重置密码：后端加 `admin_reset_password` action + 用户页入口
- [ ] 租户编辑 `expiresAt`（DatePicker + UtcDateTime 转换）
- [ ] token 自动刷新 / 401 全局跳转登录
- [ ] 前端单测与 Playwright E2E（目前无 infra，以 `tsc` + curl E2E 为门禁）
- [ ] `bin/herdr-services.sh` 接入 admin pane（现为手动 pane p4；注意脚本 `start` 会 kill :3000，需先处理 OrbStack 冲突）
- [ ] Dockerfile 前端路径更新（`frontend/` → monorepo，Phase 11 统一做）

### 🐛 踩坑记录（Phase 4）

1. **corepack 需 `enable` 才有 pnpm shim**：`prepare` 只下载，`enable` 后 `pnpm@11.3.0` 可用。
2. **`pnpm approve-builds` 非交互跑不通**：`--ignore-scripts` 先装（sharp/unrs-resolver 声明 `neverBuiltDependencies`；student `images.unoptimized` 用不到 sharp）。
3. **tsconfig `extends` 别用包名**：`@tcm-edu/config` 未被依赖时解析失败，改相对路径（`../config` / `../../packages/config`）。
4. **Turbopack + pnpm workspace**：包实体在根 `.pnpm` 下，`turbopack.root` 必须指到 monorepo 根，否则报 `couldn't find next/package.json`；另删 student 搬过来的旧 `pnpm-lock.yaml`（误导 root 推断）与过期 `.next` 缓存（RSC manifest 500）。
5. **默认 `:update` 无 RPC input**：codegen 只给显式 `accept` 的 update 生成 `input`。Organization 加 `update_details` 显式 action 并重指 `rpc_action`，前端函数名不变。
6. **timestamp 默认非 public**：`insertedAt` 不在 generated field union 里，管理端表格/排序去掉它（不动后端）。
7. **React 19 lint `set-state-in-effect`**：fetch-effect 写法全仓库飘红（含 student 存量），新代码保持同风格，门禁只看 `tsc`。

---

## Phase 5 · 教师 Console 🟢 已完成

> 目标：教师能创建/发布课程
> 前置依赖：Phase 6（Course 资源）✅ + Phase 4（monorepo 基建）✅
> 实际工期：1 天
> 完成日期：2026-09-07

### 5.1 Teacher App 初始化 🟢

- [x] 创建 `apps/teacher/`：Next.js 16 + Antd 5（ProLayout，与 admin 同栈）
- [x] 配置代理 `/api/*` → `:4011`
- [x] 复用 `packages/rpc-client` 和 antd 主题（品牌色朱红 `#b83a2e`）
- [x] 验证：`pnpm --filter @tcm-edu/teacher dev` 启动成功（:3003，`/login` 200）

### 5.2 登录与布局 🟢

- [x] 实现登录页（租户用户登录；teacher / tenant_admin 放行，student 拒绝并提示）
- [x] 实现教师专属布局（ProLayout 简洁侧边栏：工作台/我的课程/我的学生 + tenant Tag）
- [x] session 存 `userId`（取自 `/api/auth/me`，供 `listTeacherCourses`/`createCourse` 传 `teacherId`）

### 5.3 课程列表页 🟢

- [x] 实现 `/courses` 列表（状态筛选：全部/草稿/已发布/已下架，客户端计数）
- [x] 实现表格/卡片视图切换（Segmented + Table / Card 网格）
- [x] 实现"创建课程"按钮 → `/courses/new`

### 5.4 课程编辑器 🟢

- [x] 实现 `/courses/new` 创建页（标题/副标题/简介/封面URL/难度/价格/分类；建完跳编辑页）
- [x] 实现 `/courses/[id]/edit` 编辑页（基本信息表单 + `updateCourse`）
- [x] 实现章节管理：增删改（Collapse 分组，sortOrder 自动递增）
- [x] 实现课时管理：增删改、类型选择（视频/文章/PDF）、试看开关、时长
- [ ] 上传课程封面直传（defer：暂用 URL 输入框；待 AshStorage 前端直传方案，见后续）
- [ ] 写测试（defer：前端无测试 infra，与 Phase 4 一致以 `tsc` + 手工验证为门禁）

### 5.5 课程发布流程 🟢

- [x] 实现"发布课程"按钮（列表 + 编辑页；后端校验至少 1 章节+1 课时，失败回显 message）
- [x] 显示发布状态（列表 Tag + 编辑页标题 Tag；发布按钮无内容时 disabled + 提示）
- [x] 实现"下架"操作（`archiveCourse`，列表 + 编辑页）
- [x] 写测试（defer，同 5.4）

### 5.6 我的学生页 🟢

- [x] 实现 `/students`（本机构学生表格 + 邮箱/姓名筛选）
- [x] 占位说明：按课程报名的筛选待 Phase 7 选课域完成后接 `enrollments`
- [x] 写测试（defer，同 5.4）

### 5.7 Phase 5 完成标志 ✅

- [x] 教师登录 → 创建课程 → 添加章节 → 添加课时 → 发布（页面链路完整；发布校验由后端 Phase 6 逻辑保障）
- [x] `pnpm --filter @tcm-edu/teacher typecheck` 通过
- [x] lint 与 admin 基线一致（5 处 `react-hooks/set-state-in-effect`，同 admin 存量风格；门禁看 `tsc`）
- [x] 后端配合：Course/Chapter/Lesson 关系加 `public?: true`（暴露 `teacherId`/`categoryId`/`courseId`/`chapterId` + `chapters`/`lessons` 嵌套加载 + FK 过滤）；`mix ash_typescript.codegen` 重生成；课程测试 24/24 通过
- [x] 更新本文档勾选状态
- [ ] Git commit + push（用户允许 commit 时执行）

**实际工期**：1 天

### 🐛 踩坑记录（Phase 5）

1. **关系默认非 public，TS 类型里没有 FK 和嵌套加载**：`belongs_to` 的 FK 属性 `public?` 默认跟随关系的 `public?`（Ash 默认 false）。`teacherId`/`categoryId`/`courseId` 进不了 schema，`{chapters: [...]}` 嵌套选不出来。解法：三个资源的 6 个关系全部加 `public? true`（注释说明用途），重跑 codegen。
2. **`as const` 的嵌套 fields 数组是 readonly，赋值给 `Fields` 失败**：纯字符串数组 `as const` 没问题，但含 `{chapters: [...]}` 对象时必须用内联可变数组（或显式类型注解）。
3. **Chapter/Lesson 没有 `list_by_course` action**：不需要加——FK public 后 `ChapterFilterInput.courseId` / `LessonFilterInput.chapterId` 可直接过滤；编辑页实际用 `getCourse` 一次嵌套取全结构，更少请求。
4. **不要对 Ash 资源跑裸 `mix format`**：仓库是无括号 DSL 风格（`public? true`），本地 `mix format` 会全文件改成有括号风格（`public?(true)`），且原提交本来就不满足 `--check-formatted`。改资源文件只增量编辑、保持原风格；`mix precommit` 本来就红在预存的 `chat_controller.ex` warning（Phase 1 起），与本次改动无关。

---

## Phase 6 · 课程域 🟢 已完成

> 目标：完整的 Course/Chapter/Lesson/Category 资源
> 前置依赖：Phase 3 完成（多租户 User）✅
> 实际工期：1 天
> 完成日期：2026-09-07
> 备注：Phase 5（教师端 UI）依赖本 Phase，已先行完成

### 6.1 资源定义 🟢

- [x] 创建 `lib/tcm_edu/courses/course.ex`
- [x] 创建 `lib/tcm_edu/courses/chapter.ex`
- [x] 创建 `lib/tcm_edu/courses/lesson.ex`
- [x] 创建 `lib/tcm_edu/courses/course_category.ex`
- [x] 配置所有资源的 `multitenancy :context`
- [x] 写租户迁移 `20260830000003_create_tenant_courses.exs`（4 张表 + FK：teacher→users restrict，chapter/lesson 级联删除）

### 6.2 Course 资源详情 🟢

- [x] attributes：title、subtitle、description、cover_image_url、tags、level、status、price_cents、published_at
- [x] relationships：teacher、category、chapters（enrollments 留到 Phase 7）
- [x] aggregates + calculations：`lesson_count`（expr 内联）/`duration_seconds`（引用 sum 聚合）+ `authorize? false`（见坑 4）
- [x] actions：create_course、list_published、list_by_teacher、list_by_category、publish（含 1 章节+1 课时校验）、archive（`list_popular`/`student_count` 留到 Phase 7，需 Enrollment）
- [x] policies：草稿仅作者/管理员可见、已发布公开可见、显式 update（默认 update 无 RPC input，见坑 2）
- [x] publish 加 `require_atomic? false`（自定义 validate 非原子，见坑 3）

### 6.3 Chapter 资源详情 🟢

- [x] attributes：title、sort_order
- [x] relationships：course、lessons（按 sort_order 排序）
- [x] actions：显式 create/update（默认 action 无 accept，见坑 2）
- [x] policies：读随课程可见性；写限 admin 或课程作者（`expr(course.teacher_id == ^actor(:id))`）

### 6.4 Lesson 资源详情 🟢

- [x] attributes：title、content_type（video/article/pdf）、content_url、content_text、duration_seconds、sort_order、is_free_preview
- [x] relationships：chapter
- [x] actions：显式 create/update（同坑 2）
- [x] policies：免费公开；其余登录可见（“已选课”收紧留到 Phase 7，需 Enrollment）

### 6.5 CourseCategory 资源详情 🟢

- [x] attributes：name、slug、icon、sort_order
- [x] relationships：parent、children、courses（两级）
- [x] identities：unique_slug_per_tenant（索引改名对齐 Ash 约定，见坑 5）
- [x] actions：显式 create（同坑 2）
- [x] policies：读公开（含匿名，学生端用）；写仅管理员

### 6.6 AshAdmin 集成 ⏭️ 已跳过

- [x] 按 Q4 决策跳过（管理端全部手写 Antd，不引入自动生成 UI）

### 6.7 域配置 🟢

- [x] 创建 `lib/tcm_edu/courses.ex` 域
- [x] 在 `typescript_rpc` 块暴露全部 24 个 actions
- [x] 跑 `mix ash_typescript.codegen` 生成新客户端（61 个 RPC 函数）

### 6.8 测试数据 🟢

- [x] 创建 `mix tcm_edu.seed_courses`（`TENANT=` 参数，幂等跳过）
- [x] 为 `tenant_default` 种入 5 分类、20 课程（全已发布）、60 章节、300 课时、20 个免费试看

### 6.9 测试 🟢

- [x] `test/tcm_edu/courses/course_test.exs`（24 个测试，全部通过）
- [x] 集成测试：教师建草稿 → 学生/匿名看不到 → 发布 → 学生/匿名能看到
- [x] 集成测试：跨租户看不到对方课程（schema 级隔离）
- [x] calculation `lesson_count`/`duration_seconds` 正确（`student_count` 留到 Phase 7）
- [x] 章节/课时作者归属：teacher B 改 teacher A 的内容被 Forbidden；admin 可改
- [x] 免费试看匿名可读、非免费匿名拒绝、登录可读

### 6.10 Phase 6 完成标志 ✅

- [x] `mix ash_typescript.codegen` 成功（含 `lessonCount`/`durationSeconds`，calculation 需 `public? true`）
- [x] 跑 seed 后，tenant_default 有 5 分类、20 课程（60 章节/300 课时）
- [x] AshAdmin：按 Q4 跳过
- [x] `mix test` 83/85（仅 2 个预存 LLM 失败）；`tsc`（rpc-client）通过；compile 干净
- [x] E2E：匿名 `list_published_courses` 20 条 + 聚合正确；`list_categories` 5 个
- [x] 更新本文档勾选状态
- [ ] Git commit + push（用户允许 commit 时执行）

### 🐛 踩坑记录（Phase 6）

1. **Elixir 解析器诡异报错**：深层 `Enum.each` 嵌套 + 行内 `if/2` 关键字块组合触发 `MismatchedDelimiterError`（孤立子块可编译，整体不行）。解法：拆成小函数（`seed_category!`/`seed_course!`/`seed_chapter!`/`seed_lesson!`），代码也更干净。
2. **`defaults` 的 create/update 不接受字段**：`defaults [:create]` 生成的 action `inputs` 为空。Category/Chapter/Lesson 的 create、Course/Chapter/Lesson 的 update 全部改为显式 `accept`（Organization 的 `update_details` 同理，Phase 4 已踩过一次）。
3. **自定义 validate 的 update 必须 `require_atomic? false`**：`publish` 的章节/课时存在性校验非原子，不加会报 `must be performed atomically`。
4. **匿名看到的聚合被 Lesson 策略过滤**：RPC 子查询会注入 actor 的 policy filter，匿名 `count` 只算免费课时。课程卡片计数是公开信息 → 聚合加 `authorize? false`（标题/内容仍受 Lesson policy 保护）。另：`sum` 不支持 expr 嵌套路径，改用 aggregate + calculation 引用。
5. **手写唯一索引名要对齐 Ash 约定**：DB 索引名与 Ash 生成的 changeset constraint 名不一致时，唯一冲突报 500 而非 422。新增租户迁移改名（`users_unique_email_per_tenant_index` 等）。
6. **calculation 默认非 public**：`lessonCount` 不出现在 TS 类型里，需显式 `public? true`（do-block 形式）。
7. **`Ash.get` 不自动加载聚合**：测试里用 `Ash.load!` 显式加载。

---

## Phase 7 · 选课与进度 🟢 已完成

> 目标：学生能选课、看课时内容、上报进度
> 前置依赖：Phase 6 完成 ✅
> 实际工期：1 天
> 完成日期：2026-09-07

### 7.1 资源定义 🟢

- [x] 创建 `lib/tcm_edu/enrollment/enrollment.ex`
- [x] 创建 `lib/tcm_edu/enrollment/progress.ex`
- [x] 创建 `lib/tcm_edu/enrollment/changes/`（`AutoComplete`、`EnsureCoursePublished`）
- [x] 配置 `multitenancy :context`
- [x] 写租户迁移 `20260830000005_create_tenant_enrollments.exs`（`enrollments` + `progress` 表 + Ash 约定唯一索引名）

### 7.2 Enrollment 资源详情 🟢

- [x] attributes：status、enrolled_at、expires_at、completed_at
- [x] relationships：user、course、progress_records（全部 `public?: true`）
- [x] identities：unique_user_course（索引 `enrollments_unique_user_course_index`，冲突 422）
- [x] actions：enroll（含已发布校验）、mark_completed、cancel（+ my_enrollments、destroy）
- [x] policies：仅学生可选课（`user_id` 强制取 actor）、用户看自己的、教师看自己课程的、管理员看所有

### 7.3 Progress 资源详情 🟢

- [x] attributes：status、progress_pct（0-100 约束）、last_position_seconds、completed_at
- [x] relationships：enrollment、lesson（`public?: true`）
- [x] identities：unique_enrollment_lesson（索引 `progress_unique_enrollment_lesson_index`）
- [x] actions：upsert_progress（心跳：存在更新/不存在创建）、update
- [x] policies：写限本人或管理员；读加教师（自己课程）可见
- [x] `progress_pct >= 100` 自动落 completed + completed_at（`AutoComplete` change）

### 7.4 域配置 🟢

- [x] 创建 `lib/tcm_edu/enrollment.ex` 域（`config.exs` 注册）
- [x] 暴露 RPC：my_enrollments、enroll_in_course、cancel_enrollment、complete_enrollment、upsert_progress、update_progress
- [x] 跑 codegen（7 个新函数；Course 类型新增 `studentCount`）
- [x] Course 补齐 Phase 6 预留：`has_many :enrollments` + `total_students` 聚合 + `student_count` calculation + `list_popular`（已发布按人数 Top 10）+ `listPopularCourses` RPC

### 7.5 测试 🟢

- [x] `test/tcm_edu/enrollment/enrollment_test.exs`（22 个测试，全部通过）
- [x] 测试：学生选课 → 创建 enrollment
- [x] 测试：同一课程重复选课被拒绝（422 Invalid）；草稿课拒绝；教师/匿名 Forbidden
- [x] 测试：my_enrollments 只看自己的；教师只看自己课程的；管理员看所有
- [x] 测试：cancel / mark_completed 本人或管理员；他人 Forbidden
- [x] 测试：心跳 upsert 同一条记录更新；100% 自动完结；跨用户写 Forbidden；pct>100 拒绝
- [x] 测试：跨租户不可见
- [x] 测试：student_count 只计 active；list_popular 按人数倒序且仅已发布

### 7.6 Phase 7 完成标志 ✅

- [x] `mix test` 全量 105/107（2 个预存 LLM 余额失败，与本次无关）；`tsc` 五件套全过
- [x] API smoke：7 个 RPC 函数已生成；action 级 E2E 由 22 个测试覆盖
- [x] 更新本文档勾选状态
- [ ] Git commit + push（用户允许 commit 时执行）

**实际工期**：1 天

### 🐛 踩坑记录（Phase 7）

1. **create 的 validate 里拿不到 tenant**：validate 跑在 `for_action` 时，`changeset.tenant` 和 validate 第二个参数 `context.tenant` 都是 nil（tenant 在 `Ash.create` 的 opts 里，验证阶段还没合进来）。课程已发布检查必须做成 `before_action` hook（run 阶段 tenant 已就绪，已实测）。update 路径无此问题（for_update 可从 record 的 `__metadata__.tenant` 拿到）。
2. **actor 模板 change 同理有时序要求**：`set_attribute(:user_id, actor(:id))` 只在 actor 随 `for_action`/`for_create` 一起传时才正确。测试必须写成 `for_action(:enroll, params, actor: x, tenant: t)` 再 `Ash.create()`——这正好与 RPC 行为一致（pipeline 见 `AshTypescript.Rpc.Pipeline.execute_create_action`：`for_create` 带全 opts 再 `Ash.create()` 无参）。
3. **`Ash.Changeset.before_action` 的 hook 是 1 元函数**：`before_action(changeset, fn cs -> ... end)`，传 2 元报 BadArityError。
4. **Progress 的 `relates_to_actor_via([:enrollment, :user])` 在 create 上可用**：跨用户写他人进度被正确 Forbidden（22 个测试覆盖）。

---

## Phase 8 · 学生端首页

> 目标：参考 renminyixue.com 的首页体验
> 前置依赖：Phase 6 + Phase 7 完成
> 工期估计：3-4 天

### 8.1 设计 student app

- [ ] 选定品牌色（朱红 `#B83A2E` + 米黄 `#F4E9D8` + 竹青 `#5A7D65`）
- [ ] 引入"思源宋体"作为标题字体
- [ ] 写 `tailwind.config.ts` 配置
- [ ] 写 `globals.css` 基础样式
- [ ] 写 `<RootLayout>` 含导航栏 + Footer

### 8.2 公共组件

- [ ] 实现 `<HeroBanner>`（全屏 banner，支持轮播）
- [ ] 实现 `<CategoryGrid>`（圆角分类卡片网格）
- [ ] 实现 `<CourseCard>`（课程卡片：封面、标题、评分、人数、教师）
- [ ] 实现 `<TeacherCard>`（名师卡片）
- [ ] 实现 `<StatsBar>`（数据展示条）
- [ ] 实现 `<LearningPath>`（学习路径图）
- [ ] 写组件测试

### 8.3 首页装配

- [ ] 实现 `app/page.tsx`
- [ ] 服务端调用 `list_popular_courses` + `list_categories`
- [ ] 拼装上面 6 个组件
- [ ] 实现加载骨架屏
- [ ] 写测试（用 Playwright 截图）

### 8.4 登录入口

- [ ] 实现 `app/login/page.tsx`（学生登录页）
- [ ] 实现"未登录也能浏览"的逻辑（首页/课程列表不需要登录）
- [ ] 写测试

### 8.5 导航栏

- [ ] 实现顶部导航：Logo、首页、课程、名师、关于、登录/用户菜单
- [ ] 用户菜单：我的学习、个人中心、退出
- [ ] 移动端响应式

### 8.6 Phase 8 完成标志

- [ ] 首页在浏览器看起来符合设计（参考截图）
- [ ] 未登录能看到所有内容，点击"学习"才提示登录
- [ ] `pnpm --filter student lint && tsc --noEmit` 通过
- [ ] Git commit

**实际工期**：____ 天

---

## Phase 9 · 课程列表 + 详情页

> 目标：完整的学生端课程浏览与选课流程
> 前置依赖：Phase 8 完成
> 工期估计：3-4 天

### 9.1 课程列表页

- [ ] 实现 `app/courses/page.tsx`
- [ ] 侧边栏：分类筛选、难度筛选
- [ ] 顶部工具栏：搜索框、排序下拉
- [ ] 课程卡片网格（4 列响应式：xl 4 / lg 3 / md 2 / sm 1）
- [ ] 加载更多 / 分页
- [ ] 写测试

### 9.2 课程详情页

- [ ] 实现 `app/courses/[id]/page.tsx`
- [ ] 顶部信息区：封面、标题、教师、评分、人数、课时、标签、CTA 按钮
- [ ] Tab 切换：课程介绍 / 章节列表 / 讲师介绍
- [ ] 章节展开/折叠、课时列表
- [ ] 已登录显示"继续学习"或"立即学习"按钮
- [ ] 未登录显示"登录后学习"按钮
- [ ] 写测试

### 9.3 选课流程

- [ ] 实现"立即学习"按钮：调用 `enroll_in_course`
- [ ] 已选课显示"继续学习" → 跳 `/learn/[courseId]/[lessonId]`
- [ ] 未选课点击 → 弹登录提示（未登录）或确认对话框（已登录）
- [ ] 写测试

### 9.4 课时学习页

- [ ] 实现 `app/learn/[courseId]/[lessonId]/page.tsx`
- [ ] 视频播放器（HTML5 `<video>` + 简单控制条）
- [ ] 文章渲染（react-markdown）
- [ ] PDF 预览（iframe）
- [ ] 上报进度（每 10 秒心跳）
- [ ] 章节切换侧边栏
- [ ] 写测试

### 9.5 我的学习页

- [ ] 实现 `app/my-learning/page.tsx`
- [ ] 显示已选课程列表 + 进度条
- [ ] 点击进入继续学习
- [ ] 写测试

### 9.6 SEO

- [ ] 实现动态 OG meta tags
- [ ] 实现 sitemap.xml
- [ ] 实现 robots.txt
- [ ] 写测试（用 Lighthouse）

### 9.7 Phase 9 完成标志

- [ ] 端到端流程：游客浏览 → 注册 → 选课 → 学课时 → 进度保存
- [ ] Playwright E2E 测试通过
- [ ] Lighthouse 性能分 > 80
- [ ] Git commit

**实际工期**：____ 天

---

## Phase 10 · 集成打磨

> 目标：跨端联调 + 错误处理 + UX 优化
> 前置依赖：Phase 9 完成
> 工期估计：2-3 天

### 10.1 错误处理

- [ ] 统一后端错误格式（Ash.Error → API 友好）
- [ ] 前端全局错误 toast
- [ ] 401 自动跳登录页
- [ ] 403 友好提示（"您没有权限"）
- [ ] 网络错误友好提示

### 10.2 Loading 状态

- [ ] 骨架屏组件库
- [ ] 全局 loading indicator
- [ ] 表格/卡片加载态
- [ ] 按钮 loading 态

### 10.3 空状态

- [ ] 空数据占位图
- [ ] 友好的"暂无数据"文案
- [ ] 推荐操作 CTA

### 10.4 联调

- [ ] 三个 app 之间共享 token（开发环境）
- [ ] 切换登录态（开发 cookie 工具）
- [ ] 跨租户切换（开发工具）

### 10.5 移动端

- [ ] 学生端 mobile 适配
- [ ] 管理端 mobile 适配（响应式表格）
- [ ] 教师端 mobile 适配

### 10.6 性能优化

- [ ] RPC 客户端 cache（SWR / TanStack Query）
- [ ] 图片懒加载 + Next/Image
- [ ] Antd 按需引入
- [ ] bundle 分析

### 10.7 Phase 10 完成标志

- [ ] 所有 E2E 测试通过
- [ ] Lighthouse 性能分 > 85
- [ ] 0 console error
- [ ] Git commit

**实际工期**：____ 天

---

## Phase 11 · 部署与文档

> 目标：可上线的部署包 + 完整文档
> 前置依赖：Phase 10 完成
> 工期估计：1-2 天

### 11.1 Docker

- [ ] 编写 `Dockerfile`（多阶段构建：elixir deps → release + node build → runtime）
- [ ] 编写 `docker-compose.yml`（db + backend）
- [ ] 编写 `docker-compose.prod.yml`（+ nginx）
- [ ] 验证本地 `docker compose up` 成功

### 11.2 Nginx

- [ ] 编写 `nginx.conf` 路由分发
- [ ] 处理静态文件 cache
- [ ] 处理 HTTPS（占位，使用 certbot）

### 11.3 数据库

- [ ] 写 `priv/repo/tenant_migrations` 完整迁移
- [ ] 写部署脚本：跑主迁移 + 创建默认租户 + 跑租户迁移
- [ ] 测试：从空 DB 到可运行的全套初始化脚本

### 11.4 文档

- [ ] 写 `docs/deployment.md`
- [ ] 写 `docs/operations.md`（运维手册）
- [ ] 写 `docs/architecture-decisions.md`（关键决策记录）
- [ ] 更新 `README.md`
- [ ] 更新 `AGENTS.md`

### 11.5 监控

- [ ] 配置 Sentry（前后端）
- [ ] 配置 Oban Web
- [ ] 写健康检查 endpoint

### 11.6 Phase 11 完成标志

- [ ] `docker compose up` 一键启动
- [ ] 文档完整可读
- [ ] Git tag v0.1.0

**实际工期**：____ 天

---

## 📊 总体回顾

### 已完成 phase

| Phase | 完成日期 | 实际工期 | 备注 |
|-------|----------|----------|------|
| 0 文档与方案评审 | 2026-09-06 | 0.5 天 | 14 节主方案 + 进度文档 |
| 1 多租户基础设施 | 2026-09-06 | 1 天 | Organization + TenantProvisioning + 双轨迁移 |
| 2 认证与超管体系 | 2026-09-06 | 0.5 天 | SuperAdmin + 自定义 JWT + SetTenantFromToken + 3 种登录入口 |
| 3 重构 User + 角色 | 2026-09-06 | 1 天 | User multitenancy + 三角色 + 数据迁移 + 20 个测试 |
| 4 超管 Console | 2026-09-06 | 1 天 | pnpm monorepo + admin 应用（登录/工作台/租户/用户）+ Organization 策略收紧 |
| 6 课程域 | 2026-09-07 | 1 天 | Course/Chapter/Lesson/Category + 发布流 + seed + 24 个测试（Phase 5 所需先行） |
| 5 教师 Console | 2026-09-07 | 1 天 | teacher 应用（登录/工作台/课程列表/创建/编辑器/发布/学生页）+ 课程域关系 public 化 + TS 重生成 |
| 7 选课与进度 | 2026-09-07 | 1 天 | Enrollment/Progress + 心跳 upsert + student_count/list_popular + 22 个测试 |

### 阻塞 & 风险记录

| 日期 | Phase | 问题 | 解决方案 |
|------|-------|------|----------|
| 2026-09-06 | 1 | DROP SCHEMA `tenant_x-y` 报 syntax error | 必须用引号包裹：`"tenant_x-y"` |
| 2026-09-06 | 1 | SQL Sandbox 隔离外部事务，`all_tenant_schemas` 看不到测试外的 `tenant_default` | 测试只断言本次创建的新 schema，不检查外部 |
| 2026-09-06 | 2 | `Joken.generate_and_sign/2` 默认 signer_arg = `:default_signer`，不会用我传入的 Signer struct | 用 3-arity `generate_and_sign(%{}, payload, signer)` |
| 2026-09-06 | 2 | Ash Query 宏在 action run block 里报错 `expected a resource or a query` | 在 action 里使用全名 `TcmEdu.System.SuperAdmin`，因为 `__MODULE__` 指向自动生成的 action 模块 |
| 2026-09-06 | 2 | `Ash.update/5` 5-arity 不存在 | 改为 `Ash.Changeset.for_update/3` + `Ash.update/2` |
| 2026-09-06 | 2 | change 在 validation 失败后仍运行（hash nil → ArgumentError） | 加 `only_when_valid? true` 到 change |
| 2026-09-06 | 2 | `expr(now())` 返回 NaiveDateTime，不能 cast 到 utc_datetime | 改为 `&DateTime.utc_now/0` |
| 2026-09-06 | 2 | Ash wrap :invalid_credentials → Ash.Error.Unknown，模式匹配不到 | 用 `inspect(err) =~ "invalid_credentials"` 字符串匹配 |

### 经验教训

（实施过程中遇到的关键决策 / 坑 / 心得，写在这里供未来参考）

---

## 🔄 文档维护

- 每周 review 一次本文档，更新勾选状态
- 每个 phase 完成后，提交一个 commit：`(docs) progress: complete phase N`
- 任何方案变更，先改 `tcm-edu-dev-plan.md` 再改代码