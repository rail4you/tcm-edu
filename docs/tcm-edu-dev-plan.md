# TCM-Edu 主开发方案

> **状态**：草案 v1（待 review）
> **最后更新**：2025-08-30
> **目标读者**：项目 owner + 开发执行者（AI agent / 团队成员）

---

## 目录

1. [项目概述](#1-项目概述)
2. [技术架构总览](#2-技术架构总览)
3. [多租户架构设计](#3-多租户架构设计)
4. [角色与权限体系](#4-角色与权限体系)
5. [域模型设计](#5-域模型设计)
6. [后端 Ash 资源设计](#6-后端-ash-资源设计)
7. [认证与会话管理](#7-认证与会话管理)
8. [前端架构](#8-前端架构)
9. [UI 设计规范](#9-ui-设计规范)
10. [分阶段开发计划](#10-分阶段开发计划)
11. [测试与质量保证](#11-测试与质量保证)
12. [部署与运维](#12-部署与运维)
13. [风险与开放问题](#13-风险与开放问题)
14. [附录：参考资料](#14-附录参考资料)

---

## 1. 项目概述

### 1.1 业务背景

构建一个**中医教学在线平台**：

- 不同机构（中医药大学、培训机构、医院）可作为独立**租户**入驻
- 每个租户有自己的管理员、教师、学生
- 教师发布课程，学生学习课程
- 超级管理员跨租户运营整个平台

### 1.2 与参考项目的差异

| 维度 | kg-edu（参考） | tcm-edu（本项目） |
|------|----------------|---------------------|
| 业务领域 | 通用知识图谱教育 | 垂直：中医 |
| 租户数量 | 中等（教育机构） | 较多（覆盖中医类机构） |
| 租户隔离 | PostgreSQL schema | 同上 |
| 课程复杂度 | 课程/章节/视频/作业/考试/能力图谱 | 课程/章节/课时（简化） |
| 前端 | 单 AntD Pro 应用 | **三套前端**：管理端/教师端(Antd) + 学生端(React) |
| AI 能力 | Jido agents 较重 | 复用现有 Jido 能力（AI 助教） |

### 1.3 关键参考

- **后端架构模式**：`/Users/bai/projects/kg-edu/backend/kg_edu/lib/kg_edu/accounts/organization.ex`、`ash_migration_manager.ex`、`tenant_manager.ex`、`lib/kg_edu_web/plug/set_tenant_from_token.ex`
- **UI 参考**：人民医学网（轮播 + 分类 + 课程卡片 + 名师）
- **现有 tcm-edu 资源**：`Accounts`（RBAC 已就位）、`Todo/Post/Chat`（demo 资源）

---

## 2. 技术架构总览

### 2.1 总体架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                          客户端 (Browser)                         │
├──────────────────┬───────────────────┬──────────────────────────┤
│  学生端 (公开)    │   教师端 (登录后)  │     管理端 (登录后)        │
│  Next.js +       │   Next.js + Antd  │   Next.js + Antd Pro     │
│  自定义 React    │   教师/管理员视图   │   超管/租户管理员视图      │
└────────┬─────────┴──────────┬─────────┴──────────┬──────────────┘
         │                    │                    │
         │  HTTP (3001/3002/3003) + JWT Bearer    │
         ▼                    ▼                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                Phoenix 1.8 + AshTypescript RPC (:4011)            │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Phoenix Endpoint + Plug Pipeline                            │ │
│  │   ├─ CORS                                                  │ │
│  │   ├─ RetrieveFromBearer / SetActor (AshAuthentication)    │ │
│  │   ├─ SetTenantFromToken (extracted tenant from JWT)        │ │
│  │   └─ Router → AshTypescriptRpcController.run/2             │ │
│  └────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Ash Domains                                                │ │
│  │   ├─ System (public schema)                                │ │
│  │   │   • TcmEdu.System.Organization                        │ │
│  │   │   • TcmEdu.System.SuperAdmin (or User in system)      │ │
│  │   ├─ Accounts (tenant schema)                              │ │
│  │   │   • TcmEdu.Accounts.User                              │ │
│  │   ├─ Courses (tenant schema)                               │ │
│  │   │   • TcmEdu.Accounts.Course                             │ │
│  │   │   • TcmEdu.Accounts.Chapter                           │ │
│  │   │   • TcmEdu.Accounts.Lesson                             │ │
│  │   ├─ Enrollment (tenant schema)                            │ │
│  │   │   • TcmEdu.Enrollment.Enrollment                       │ │
│  │   │   • TcmEdu.Enrollment.Progress                        │ │
│  │   └─ Chat / Storage (复用现有)                              │ │
│  └────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Oban workers (background jobs)                              │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    PostgreSQL (:5433)                            │
│  ┌────────────┐  ┌─────────────────┐  ┌──────────────────────┐ │
│  │   public   │  │ tenant_default  │  │ tenant_<slug>        │ │
│  │  (系统)    │  │ (默认租户)       │  │ (业务租户)            │ │
│  │            │  │                 │  │                      │ │
│  │ organizations│ │  users         │  │  users                │ │
│  │ schema_   │  │  courses       │  │  courses              │ │
│  │   migrations│  │  chapters     │  │  chapters             │ │
│  │            │  │  lessons      │  │  lessons              │ │
│  │            │  │  enrollments  │  │  enrollments          │ │
│  └────────────┘  └─────────────────┘  └──────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 技术栈清单

| 层 | 技术 | 版本 | 备注 |
|----|------|------|------|
| 后端 | Elixir | 1.18 / OTP 27 | 现有项目要求 |
| 后端 | Phoenix | 1.8 | 现有 |
| 后端 | Ash Framework | 3.x | 现有 |
| 后端 | AshPostgres | 2.6+ | 现有 |
| 后端 | AshAuthentication | 4.x | 现有（已用） |
| 后端 | AshTypescript | 0.6+ | 现有 |
| 后端 | AshAdmin | 0.13+ | **新增**（自动生成 admin CRUD） |
| 数据库 | PostgreSQL | 13+ | 现有 |
| 后台任务 | Oban | latest | 现有 |
| AI | Jido / Jido AI | 2.x | 现有（用于 AI 助教） |
| 前端 | Next.js | 16.2.x | 现有（学生端基线） |
| 前端 | React | 19.x | 现有 |
| 前端 | TypeScript | 5.x | 现有 |
| 前端 | Tailwind | 4.x | 现有（学生端） |
| 前端 | Antd | 5.x | **新增**（管理端 + 教师端） |
| 前端 | Vite (可选) | 5.x | 仅 Antd 端可换 Vite 提速 |

---

## 3. 多租户架构设计

### 3.1 为什么选 schema 隔离？

| 隔离方式 | 优点 | 缺点 | 适合场景 |
|----------|------|------|----------|
| **每租户一个 DB** | 强隔离、可独立备份 | 运维复杂、连接数高 | 银行级隔离 |
| **每租户一个 schema**（✅ 选） | 强隔离 + 共享连接池 + 易迁移 | 跨租户查询需手动 union | 中等租户数 + 强隔离 |
| 每租户一个 tenant_id 列 | 简单、跨租户查询方便 | 隔离弱、易泄漏 | SaaS 小工具 |

→ **选择 schema 隔离**：参考 kg-edu，PG 原生支持、AshPostgres 直接管理。

### 3.2 Schema 命名与初始化

```
public         → 系统级（organizations, super_admins, schema_migrations_main）
tenant_default → 默认租户（用于系统演示 + 首次安装数据）
tenant_<slug>  → 业务租户
  - slug: kebab-case 短名（如 "tcm-university"、"guangzhou-medical"）
  - 由超管创建租户时指定
```

> **设计决策（待确认）**：slug 唯一性 + 长度限制（≤ 32 字符，匹配 `[a-z0-9-]`）

### 3.3 Ash 多租户实现

#### 3.3.1 资源策略

**系统级资源**（public schema）：
- `TcmEdu.System.Organization`：租户元数据
- 无 `multitenancy` 块 → 数据在 `public` 表中

**租户级资源**（tenant schema）：
- 所有 `Users/Courses/Chapters/Lessons/Enrollments/...`
- 在资源中声明：
  ```elixir
  multitenancy do
    strategy :context   # tenant 由请求上下文决定
  end

  postgres do
    table "users"
    repo TcmEdu.Repo
    # 多租户资源不需要 manage_tenant；Organization 资源独占 manage_tenant
  end

  defimpl Ash.ToTenant do
    def to_tenant(%Organization{schema_name: schema_name}, _resource), do: schema_name
    def to_tenant(_, _), do: nil
  end
  ```

#### 3.3.2 Repository 配置

```elixir
# lib/tcm_edu/repo.ex
defmodule TcmEdu.Repo do
  use AshPostgres.Repo, otp_app: :tcm_edu

  # 让所有 tenant query 默认带 search_path
  def all_tenants do
    # 返回所有租户 schema 名（用于跨租户管理）
    query = "SELECT nspname FROM pg_namespace WHERE nspname LIKE 'tenant_%'"
    {:ok, %{rows: rows}} = __MODULE__.query(query)
    Enum.map(rows, fn [name] -> name end)
  end
end
```

### 3.4 租户解析（请求 → 上下文）

```
HTTP Request
   ↓
JWT: { sub, tenant, role, ... }
   ↓
Plug SetTenantFromToken
   ↓
  conn.private[:ash_actor] = user
  conn.private[:ash_tenant] = "tenant_default"
   ↓
AshTypescriptRpcController.run/2
   ↓
Ash.Query.for_read(..., actor: user, tenant: tenant)
   ↓
Tenanted Repo 查询（自动 SET search_path TO tenant_default, public）
```

#### 3.4.1 JWT 中的 `tenant` claim

```elixir
# 在 AshAuthentication token 中携带 tenant
authentication do
  tokens do
    enabled? true
    token_resource TcmEdu.Accounts.Token
    # 把 actor 的 tenant 写入 JWT
    store_all_tokens? true
    require_token_presence_for_authentication? true
  end
end
```

→ 需要在 token 中加 `tenant` 字段。**关键修改点**：扩展 `AshAuthentication.Jwt` 或自定义 token signer。

#### 3.4.2 Plug 实现

```elixir
# lib/tcm_edu_web/plugs/set_tenant_from_token.ex
defmodule TcmEduWeb.Plugs.SetTenantFromToken do
  import Plug.Conn
  alias TcmEdu.System.Organization

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- AshAuthentication.Jwt.peek(token),
         %{"tenant" => tenant, "sub" => subject} <- claims,
         tenant when tenant != "" and tenant != nil,
         {:ok, user} <- load_user(subject, tenant) do
      conn
      |> put_private(:ash_actor, user)
      |> put_private(:ash_tenant, tenant)
      |> put_private(:ash_context, %{tenant: tenant, actor: user})
    else
      _ -> conn
    end
  end

  defp load_user(subject, tenant) do
    user_id = extract_user_id(subject)
    TcmEdu.Accounts.User
    |> Ash.Query.filter(id == ^user_id)
    |> Ash.read_one(tenant: tenant)
  end
end
```

> super_admin 没有 tenant（或 tenant = `public`），需要特殊处理 —— 见 §4 角色设计。

### 3.5 数据迁移策略

#### 3.5.1 双轨迁移

```
priv/
├── repo/
│   ├── migrations/             # 主迁移（public schema + 资源快照）
│   │   ├── 20250101000000_create_organizations.exs
│   │   └── ...
│   └── tenant_migrations/     # 租户迁移（应用到所有 tenant_* schema）
│       ├── 20250101000000_create_tenant_users.exs
│       ├── 20250101000001_create_tenant_courses.exs
│       └── ...
```

#### 3.5.2 迁移命令

```elixir
# mix/tasks/migrate.exs (自定义)
defmodule Mix.Tasks.TcmEdu.Migrate do
  @moduledoc """
  1. 跑主迁移（public schema）
  2. 创建默认租户 'tenant_default'（如果不存在）
  3. 为所有现有租户跑租户迁移
  """

  def run(_) do
    Mix.Task.run("ash.migrate")     # 主迁移
    ensure_default_tenant()          # 默认租户
    Enum.each(TcmEdu.Repo.all_tenants(), &run_tenant_migrations/1)
  end
end
```

#### 3.5.3 迁移生成流程

```bash
# 修改资源后
mix ash.codegen add_courses        # 生成主迁移 + 资源快照
# 手动复制到 tenant_migrations（用脚本自动）

# 应用迁移
mix tcm_edu.migrate                # 主迁移 + 所有租户迁移
```

---

## 4. 角色与权限体系

### 4.1 角色定义

| 角色 | 居住 schema | 范围 | 核心权限 |
|------|-------------|------|----------|
| `super_admin` | `public`（或 `tenant_default`） | 全平台 | 跨租户管理：创建租户、查询所有租户数据 |
| `tenant_admin` | `tenant_<slug>` | 单租户 | 管理本租户用户、查看本租户课程 |
| `teacher` | `tenant_<slug>` | 单租户 | 创建/编辑自己的课程、上传课时 |
| `student` | `tenant_<slug>` | 单租户 | 浏览课程、选课、学习 |

### 4.2 super_admin 的存储方案（待确认）

> **决策点**：超管存在哪？

| 方案 | 优点 | 缺点 |
|------|------|------|
| **A. 存在 `public` schema** | 真正全局，与租户完全解耦 | 需要独立的 User schema（不能复用 Accounts.User） |
| **B. 存在 `tenant_default`** | 复用 User 资源 | 默认租户被污染；删除 `tenant_default` 会丢超管 |
| **C. 每个租户都有自己的 `super_admin`（kg-edu 方案）** | 单一 User 表 | 不存在"真正跨租户"的超管，需要逐 schema 登录 |

→ **推荐方案 A**：在 `public` schema 中建独立的 `super_admins` 表（带 `hashed_password`、邮箱）。简单、清晰。

```elixir
# lib/tcm_edu/system/super_admin.ex
defmodule TcmEdu.System.SuperAdmin do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypescript.Resource]

  postgres do
    table "super_admins"
    repo TcmEdu.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end
    attribute :name, :string, public? true
    attribute :hashed_password, :string do
      allow_nil? false
      sensitive? true
    end
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_email, [:email]
  end

  actions do
    defaults [:read, :destroy]

    create :register do
      accept [:email, :name]
      argument :password, :string, allow_nil?: false, sensitive?: true
      change {TcmEdu.System.Changes.HashPassword, []}
    end

    read :sign_in_with_password do
      get? true
      argument :email, :string, allow_nil?: false
      argument :password, :string, allow_nil?: false, sensitive?: true

      validate fn changeset, _ ->
        # 校验密码，返回用户或 :invalid_credentials
      end

      metadata :token, :string do
        description "JWT for super admin (tenant claim = 'public')"
        allow_nil? false
      end
    end
  end

  typescript do
    type_name "SuperAdmin"
  end
end
```

### 4.3 JWT 中 token 的 `tenant` 字段

```json
{
  "sub": "user?id=<uuid>",
  "tenant": "tenant_default" | "public",        //  ← 决定 Ash context
  "role": "super_admin" | "tenant_admin" | "teacher" | "student",
  "exp": 1234567890
}
```

### 4.4 权限矩阵

| 资源/动作 | super_admin | tenant_admin | teacher | student | 匿名 |
|-----------|:-----------:|:------------:|:-------:|:-------:|:----:|
| 创建租户 | ✅ | ❌ | ❌ | ❌ | ❌ |
| 删除租户 | ✅ | ❌ | ❌ | ❌ | ❌ |
| 列租户 | ✅ | ❌ | ❌ | ❌ | ❌ |
| 列本租户用户 | ✅ | ✅ | ✅ | ❌ | ❌ |
| 创建用户 | ✅ | ✅ | ❌ | ❌ | ❌ |
| 改用户角色 | ✅ | ✅（除 super） | ❌ | ❌ | ❌ |
| 列课程（草稿） | ✅ | ✅ | ✅（自己） | ❌ | ❌ |
| 列课程（已发布） | ✅ | ✅ | ✅ | ✅ | ✅ |
| 创建课程 | ✅ | ✅ | ✅ | ❌ | ❌ |
| 编辑课程 | ✅ | ✅ | ✅（自己） | ❌ | ❌ |
| 选课 | ❌ | ❌ | ❌ | ✅ | ❌ |
| 查看课时内容 | ✅ | ✅ | ✅ | ✅（已选） | ❌ |

### 4.5 Ash Policy 设计示例

```elixir
# lib/tcm_edu/accounts/course.ex (节选)
policies do
  bypass actor_attribute_equals(:role, :super_admin) do
    authorize_if always()
  end

  policy action_type(:read) do
    # 教师/管理员可看所有；学生只能看已发布的
    authorize_if expr(publish_status == true)
    authorize_if actor_attribute_equals(:role, [:teacher, :tenant_admin])
    authorize_if relates_to_actor_via(:teacher)  # 自己的课
  end

  policy action_type(:create) do
    authorize_if actor_attribute_equals(:role, [:teacher, :tenant_admin])
  end

  policy action_type(:update) do
    authorize_if actor_attribute_equals(:role, :tenant_admin)
    authorize_if relates_to_actor_via(:teacher)  # 自己的课
  end
end
```

---

## 5. 域模型设计

### 5.1 ER 关系总览

```
public schema:
  organizations ────────────────────┐
                                   │  1:N (via schema_name)
                                   ▼
tenant_<slug> schema:                ┌────────────────────────────┐
  users ───────┬──────────────────► │ courses                    │
               │                    │   ├─ chapters              │
               │                    │   │   └─ lessons           │
               │                    │   └─ cover_image (storage) │
               ▼                    ├────────────────────────────┤
  enrollments (N:M users ↔ courses) │ progress                   │
               │                    │   └─ user × lesson         │
               ▼                    └────────────────────────────┘
  progress
```

### 5.2 实体清单

#### 系统域（public schema）

| 实体 | 描述 | 字段 |
|------|------|------|
| `Organization` | 租户/机构 | id, name, slug, schema_name, contact_email, contact_phone, status, plan, created_at, expires_at |
| `SuperAdmin` | 超级管理员 | id, email, name, hashed_password, last_login_at, created_at |
| `Plan` | 套餐（可选） | id, name, max_teachers, max_students, features (jsonb), price_cents |
| `SystemConfig` | 系统设置（单例） | id, settings (jsonb) |

#### 租户域（tenant_<slug> schema）

| 实体 | 描述 | 字段 |
|------|------|------|
| `User` | 租户内用户 | id, email, name, role(tenant_admin/teacher/student), avatar_url, bio, phone, hashed_password, status(active/disabled), created_at |
| `CourseCategory` | 课程分类 | id, name, slug, parent_id (nullable, 支持 2 级), icon, sort_order |
| `Course` | 课程 | id, title, subtitle, description, cover_image_url, teacher_id, category_id, status(draft/published/archived), price_cents, level(:beginner/:intermediate/:advanced), tags (string[]), student_count (counter), published_at |
| `Chapter` | 章节 | id, course_id, title, sort_order |
| `Lesson` | 课时 | id, chapter_id, title, content_type(:video/:article/:pdf), content_url, duration_seconds, sort_order, is_free_preview |
| `Enrollment` | 选课记录 | id, user_id, course_id, enrolled_at, expires_at, status(:active/:cancelled/:completed) |
| `Progress` | 学习进度 | id, enrollment_id, lesson_id, status(:not_started/:in_progress/:completed), progress_pct, last_position_seconds, completed_at |

### 5.3 关键关系细节

#### 5.3.1 `Course.student_count`

聚合字段，由 `Enrollment` 派生：

```elixir
# Course resource
aggregates do
  count :student_count, :enrollments do
    filter expr(status == :active)
  end
end
```

#### 5.3.2 `Course.lessons`（跨章节）

```elixir
# Course resource
relationships do
  has_many :chapters, Chapter do
    sort sort_order: :asc
  end

  # 通过 chapters 间接拿 lessons（用计算字段）
end

calculations do
  calculate :total_lessons, :integer, expr(count(chapters.lessons))
  calculate :total_duration, :integer, expr(sum(chapters.lessons.duration_seconds))
end
```

#### 5.3.3 `User.enrolled_courses`

```elixir
# User resource
relationships do
  has_many :enrollments, Enrollment
  many_to_many :enrolled_courses, Course do
    through Enrollment
    source_attribute_on_join_resource :user_id
    destination_attribute_on_join_resource :course_id
  end
end
```

### 5.4 关键业务规则

#### 5.4.1 课程发布规则

- 草稿课程仅作者和管理员可见
- 发布需至少 1 个章节 + 1 个课时
- 发布后 `published_at` 自动设为 `now()`
- 下架（archived）保留所有数据，可重新上架

#### 5.4.2 选课规则

- 学生只能选已发布课程
- 同一课程不可重复选课
- 免费课程：直接创建 Enrollment
- 付费课程：需先创建支付订单（未来扩展）

#### 5.4.3 权限继承

- `tenant_admin` 自动拥有所有 teacher 权限
- 同一用户可在不同租户有不同角色（理论上支持，但 v1 不实现）

---

## 6. 后端 Ash 资源设计

> 本节列出每个 Ash 资源的关键设计点。完整代码在 Phase 实施时编写。

### 6.1 系统域资源

#### 6.1.1 `TcmEdu.System.Organization`

```elixir
defmodule TcmEdu.System.Organization do
  use Ash.Resource,
    domain: TcmEdu.System,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypescript.Resource]

  postgres do
    table "organizations"
    repo TcmEdu.Repo

    # 关键：声明 schema 由本资源管理
    manage_tenant do
      template ["tenant_", :slug]   # 如 tenant_default、tenant_tcm-uni
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :slug, :string do
      allow_nil? false
      public? true
      constraints match: ~r/^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$/
    end

    attribute :schema_name, :string do
      # 由 create 钩子自动设置：schema_name = "tenant_" <> slug
      allow_nil? true
      public? true
    end

    attribute :contact_email, :string, public?: true
    attribute :contact_phone, :string, public?: true
    attribute :description, :string, public?: true
    attribute :logo_url, :string, public?: true

    attribute :status, :atom do
      default :active
      constraints one_of: [:active, :suspended, :archived]
      public? true
    end

    attribute :plan, :atom do
      default :free
      constraints one_of: [:free, :pro, :enterprise]
      public? true
    end

    attribute :expires_at, :utc_datetime, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_slug, [:slug]
  end

  code_interface do
    define :create_organization, action: :create_with_schema
    define :list_organizations, action: :read
    define :get_organization, action: :read, get_by: [:id]
    define :update_organization, action: :update
    define :archive_organization, action: :archive
  end

  actions do
    defaults [:read, :update]

    create :create_with_schema do
      accept [:name, :slug, :contact_email, :contact_phone, :description, :logo_url, :plan]

      change fn changeset, _context ->
        slug = Ash.Changeset.get_attribute(changeset, :slug)
        Ash.Changeset.change_attribute(changeset, :schema_name, "tenant_" <> slug)
      end

      change after_action(fn _changeset, org, _context ->
        # 1. 创建 schema
        # 2. 跑租户迁移
        # 3. 创建初始 tenant_admin 用户（用 create_with_initial_admin）
        TcmEdu.TenantProvisioning.provision_tenant(org)
        {:ok, org}
      end)
    end

    update :archive do
      # 软删除，保留数据
      accept []
      change set_attribute(:status, :archived)
    end

    destroy :destroy do
      require_atomic? false
      change fn changeset, _context ->
        # 硬删除：DROP SCHEMA CASCADE + 删除 record
        schema_name = changeset.data.schema_name
        if schema_name, do: TcmEdu.Repo.query("DROP SCHEMA IF EXISTS #{schema_name} CASCADE")
        changeset
      end
    end
  end

  policies do
    # 只有 super_admin 可以操作 Organization
    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:role, :super_admin)
    end
  end

  typescript do
    type_name "Organization"
  end
end
```

#### 6.1.2 `TcmEdu.TenantProvisioning`

```elixir
defmodule TcmEdu.TenantProvisioning do
  @moduledoc """
  创建新租户的全套流程：创建 schema → 跑迁移 → 创建初始 admin 用户。
  """

  alias TcmEdu.System.Organization

  def provision_tenant(%Organization{schema_name: schema_name} = org) do
    with :ok <- create_schema(schema_name),
         :ok <- run_tenant_migrations(schema_name),
         {:ok, _admin} <- create_initial_admin(org) do
      :ok
    end
  end

  defp create_schema(schema_name) do
    TcmEdu.Repo.query("CREATE SCHEMA IF NOT EXISTS #{schema_name}")
  end

  defp run_tenant_migrations(schema_name) do
    # 跑 priv/repo/tenant_migrations/*.exs 到 schema_name
    Ecto.Migrator.with_repo(TcmEdu.Repo, fn repo ->
      Ecto.Migrator.run(
        repo,
        "priv/repo/tenant_migrations",
        :up,
        all: true,
        prefix: schema_name
      )
    end)
  end

  defp create_initial_admin(org) do
    # 在 tenant schema 中创建第一个 tenant_admin 用户
    # 临时密码或邮件邀请（v1 用临时密码）
    {:ok, _} =
      TcmEdu.Accounts.User
      |> Ash.Changeset.for_action(:register_with_role, %{
        email: org.contact_email,
        password: random_password(),
        role: :tenant_admin
      })
      |> Ash.create(tenant: org.schema_name)
  end
end
```

### 6.2 租户域资源（节选）

#### 6.2.1 `TcmEdu.Accounts.User`（重写现有）

```elixir
defmodule TcmEdu.Accounts.User do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication, AshTypescript.Resource],
    authorizers: [Ash.Policy.Authorizer],
    domain: TcmEdu.Accounts

  authentication do
    strategies do
      password :password do
        identity_field :email
        hash_provider AshAuthentication.BcryptProvider
      end
    end

    tokens do
      enabled? true
      token_resource TcmEdu.Accounts.Token
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :name, :string, public?: true
    attribute :avatar_url, :string, public?: true
    attribute :phone, :string, public?: true
    attribute :bio, :string, public?: true
    attribute :job_title, :string, public?: true   # 教师：职称

    attribute :hashed_password, :string do
      allow_nil? false
      sensitive? true
    end

    attribute :role, :atom do
      allow_nil? false
      default :student
      constraints one_of: [:tenant_admin, :teacher, :student]
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      constraints one_of: [:active, :disabled]
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_email, [:email]
  end

  relationships do
    has_many :taught_courses, TcmEdu.Courses.Course do
      destination_attribute :teacher_id
    end
    has_many :enrollments, TcmEdu.Enrollment.Enrollment
  end

  actions do
    defaults [:read, :update, :destroy]

    read :get_by_subject do
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    read :list_students do
      filter expr(role == :student)
    end

    read :list_teachers do
      filter expr(role == :teacher)
    end

    read :list_admins do
      filter expr(role == :tenant_admin)
    end

    create :register_with_role do
      accept [:email, :name, :phone, :role]
      argument :password, :string, allow_nil?: false, sensitive?: true
      change set_context(%{strategy_name: :password})
      change AshAuthentication.GenerateTokenChange
      change AshAuthentication.Strategy.Password.HashPasswordChange
    end

    update :change_password do
      require_atomic? false
      accept []
      argument :current_password, :string, sensitive?: true, allow_nil?: false
      argument :password, :string, sensitive?: true, allow_nil?: false,
        constraints: [min_length: 8]
      validate confirm(:password, :password)
      validate {AshAuthentication.Strategy.Password.PasswordValidation,
                strategy_name: :password, password_argument: :current_password}
      change {AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password}
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    bypass actor_attribute_equals(:role, :super_admin) do
      authorize_if always()
    end

    # tenant_admin 可以管理本租户用户（除其他 admin）
    policy [action(:list_students), action(:list_teachers), action(:list_admins),
            action(:register_with_role)] do
      authorize_if actor_attribute_equals(:role, :tenant_admin)
    end

    policy [action(:update), action(:destroy)] do
      authorize_if actor_attribute_equals(:role, :tenant_admin)
      authorize_if expr(id == ^actor(:id))   # 用户改自己
    end
  end

  typescript do
    type_name "User"
  end
end
```

#### 6.2.2 `TcmEdu.Courses.Course`

```elixir
defmodule TcmEdu.Courses.Course do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypescript.Resource, AshAdmin.Resource],  # ← AshAdmin 自动生成 admin UI
    authorizers: [Ash.Policy.Authorizer],
    domain: TcmEdu.Courses

  multitenancy do
    strategy :context
  end

  postgres do
    table "courses"
    repo TcmEdu.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :subtitle, :string, public?: true
    attribute :description, :string, public?: true
    attribute :cover_image_url, :string, public?: true
    attribute :tags, {:array, :string}, default: [], public?: true
    attribute :level, :atom do
      default :beginner
      constraints one_of: [:beginner, :intermediate, :advanced]
      public? true
    end
    attribute :status, :atom do
      default :draft
      constraints one_of: [:draft, :published, :archived]
      public? true
    end
    attribute :price_cents, :integer, default: 0, public?: true
    attribute :published_at, :utc_datetime, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :teacher, TcmEdu.Accounts.User do
      allow_nil? false
    end
    belongs_to :category, TcmEdu.Courses.CourseCategory
    has_many :chapters, TcmEdu.Courses.Chapter do
      sort sort_order: :asc
    end
    has_many :enrollments, TcmEdu.Enrollment.Enrollment
  end

  aggregates do
    count :student_count, :enrollments do
      filter expr(status == :active)
    end
  end

  calculations do
    calculate :total_lessons, :integer, expr(count(chapters.lessons))
    calculate :total_duration, :integer, expr(sum(chapters.lessons.duration_seconds))
  end

  actions do
    defaults [:read, :update, :destroy]

    read :list_published do
      filter expr(status == :published)
    end

    read :list_by_teacher do
      argument :teacher_id, :uuid, allow_nil?: false
      filter expr(teacher_id == ^arg(:teacher_id))
    end

    read :list_by_category do
      argument :category_id, :uuid, allow_nil?: false
      filter expr(category_id == ^arg(:category_id))
    end

    read :list_popular do
      prepare build(sort: [student_count: :desc], limit: 10)
    end

    create :create_course do
      accept [:title, :subtitle, :description, :cover_image_url, :tags,
              :level, :price_cents, :category_id]
      argument :teacher_id, :uuid, allow_nil?: false
      change set_attribute(:teacher_id, arg(:teacher_id))
    end

    update :publish do
      accept []
      validate fn cs, _ ->
        # 校验：至少有 1 章节 + 1 课时
        course = cs.data
        if TcmEdu.Courses.Chapter
           |> Ash.Query.filter(course_id == ^course.id)
           |> Ash.read_one(tenant: cs.context.tenant) == {:ok, nil} do
          {:error, field: :chapters, message: "至少需要 1 个章节"}
        else
          :ok
        end
      end
      change set_attribute(:status, :published)
      change set_attribute(:published_at, expr(now()))
    end

    update :archive do
      accept []
      change set_attribute(:status, :archived)
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :super_admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      # 任何人都能看已发布课程（包括未登录）
      authorize_if expr(status == :published)
      # 教师/管理员可看所有
      authorize_if actor_attribute_equals(:role, [:tenant_admin, :teacher])
      # 教师可看自己的
      authorize_if relates_to_actor_via(:teacher)
    end

    policy action_type(:create) do
      authorize_if actor_attribute_equals(:role, [:tenant_admin, :teacher])
    end

    policy action_type(:update) do
      authorize_if actor_attribute_equals(:role, :tenant_admin)
      authorize_if relates_to_actor_via(:teacher)
    end

    policy action_type(:destroy) do
      authorize_if actor_attribute_equals(:role, :tenant_admin)
    end
  end

  typescript do
    type_name "Course"
  end
end
```

#### 6.2.3 `TcmEdu.Courses.Chapter` & `TcmEdu.Courses.Lesson`

```elixir
defmodule TcmEdu.Courses.Chapter do
  use Ash.Resource, ...
  multitenancy do; strategy :context; end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :sort_order, :integer, default: 0, public?: true
  end

  relationships do
    belongs_to :course, TcmEdu.Courses.Course
    has_many :lessons, TcmEdu.Courses.Lesson do
      sort sort_order: :asc
    end
  end

  actions do
    defaults [:read, :create, :update, :destroy]
  end

  policies do
    bypass actor_attribute_equals(:role, [:super_admin, :tenant_admin]) do
      authorize_if always()
    end
    policy action_type([:create, :update, :destroy]) do
      authorize_if relates_to_actor_via(:course, :teacher)
    end
  end
end

defmodule TcmEdu.Courses.Lesson do
  use Ash.Resource, ...
  multitenancy do; strategy :context; end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :content_type, :atom do
      default :video
      constraints one_of: [:video, :article, :pdf]
      public?: true
    end
    attribute :content_url, :string, public?: true
    attribute :content_text, :string, public?: true   # 文章类课时
    attribute :duration_seconds, :integer, default: 0, public?: true
    attribute :sort_order, :integer, default: 0, public?: true
    attribute :is_free_preview, :boolean, default: false, public?: true
  end

  relationships do
    belongs_to :chapter, TcmEdu.Courses.Chapter
  end

  actions do
    defaults [:read, :create, :update, :destroy]
  end

  policies do
    bypass actor_attribute_equals(:role, [:super_admin, :tenant_admin]) do
      authorize_if always()
    end
    # 学生看课时内容时检查：免费预览 OR 已选课
    policy action(:read) do
      authorize_if expr(is_free_preview == true)
      authorize_if actor_present()
      authorize_if exists(enrollments, expr(user_id == ^actor(:id) and status == :active))
    end
  end
end
```

#### 6.2.4 `TcmEdu.Courses.CourseCategory`

```elixir
defmodule TcmEdu.Courses.CourseCategory do
  use Ash.Resource, ...
  multitenancy do; strategy :context; end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :slug, :string, allow_nil?: false, public?: true
    attribute :icon, :string, public?: true
    attribute :sort_order, :integer, default: 0, public?: true
  end

  relationships do
    belongs_to :parent, self_type do
      allow_nil? true   # 支持 2 级分类
    end
    has_many :children, self_type
    has_many :courses, TcmEdu.Courses.Course
  end

  identities do
    identity :unique_slug_per_tenant, [:slug]   # schema 内唯一
  end
end
```

#### 6.2.5 `TcmEdu.Enrollment.Enrollment` & `Progress`

```elixir
defmodule TcmEdu.Enrollment.Enrollment do
  use Ash.Resource, ...
  multitenancy do; strategy :context; end

  attributes do
    uuid_primary_key :id
    attribute :status, :atom do
      default :active
      constraints one_of: [:active, :cancelled, :completed]
      public?: true
    end
    attribute :enrolled_at, :utc_datetime, default: &DateTime.utc_now/0, public?: true
    attribute :expires_at, :utc_datetime, public?: true
    attribute :completed_at, :utc_datetime, public?: true
  end

  relationships do
    belongs_to :user, TcmEdu.Accounts.User
    belongs_to :course, TcmEdu.Courses.Course
    has_many :progress_records, TcmEdu.Enrollment.Progress
  end

  identities do
    identity :unique_user_course, [:user_id, :course_id]
  end

  actions do
    defaults [:read]

    create :enroll do
      accept [:course_id]
      change set_attribute(:user_id, actor(:id))   # 强制用 actor
      validate fn cs, _ ->
        # 不允许重复选课
        user_id = Ash.Changeset.get_attribute(cs, :user_id)
        course_id = Ash.Changeset.get_attribute(cs, :course_id)
        if has_existing?(user_id, course_id) do
          {:error, field: :course_id, message: "已选过此课程"}
        else
          :ok
        end
      end
    end

    update :mark_completed do
      change set_attribute(:status, :completed)
      change set_attribute(:completed_at, expr(now()))
    end
  end

  policies do
    bypass actor_attribute_equals(:role, [:super_admin, :tenant_admin, :teacher]) do
      authorize_if always()
    end
    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)   # 自己的记录
    end
    policy action(:enroll) do
      authorize_if actor_attribute_equals(:role, :student)
    end
  end
end

defmodule TcmEdu.Enrollment.Progress do
  use Ash.Resource, ...
  multitenancy do; strategy :context; end

  attributes do
    uuid_primary_key :id
    attribute :status, :atom do
      default :not_started
      constraints one_of: [:not_started, :in_progress, :completed]
      public?: true
    end
    attribute :progress_pct, :integer, default: 0, public?: true
    attribute :last_position_seconds, :integer, default: 0, public?: true
    attribute :completed_at, :utc_datetime, public?: true
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :enrollment, TcmEdu.Enrollment.Enrollment
    belongs_to :lesson, TcmEdu.Courses.Lesson
  end

  actions do
    defaults [:read, :update]
  end

  policies do
    # 用户只能更新自己的进度
    policy action(:update) do
      authorize_if expr(enrollment.user_id == ^actor(:id))
    end
  end
end
```

### 6.3 Ash 域（Domain）配置

```elixir
# lib/tcm_edu/system.ex
defmodule TcmEdu.System do
  use Ash.Domain, otp_app: :tcm_edu, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource TcmEdu.System.Organization do
      rpc_action :list_organizations, :read
      rpc_action :create_organization, :create_with_schema
      rpc_action :update_organization, :update
      rpc_action :archive_organization, :archive
      rpc_action :delete_organization, :destroy
    end

    resource TcmEdu.System.SuperAdmin do
      rpc_action :super_admin_sign_in, :sign_in_with_password
    end
  end

  resources do
    resource TcmEdu.System.Organization
    resource TcmEdu.System.SuperAdmin
    resource TcmEdu.System.Plan
  end
end

# lib/tcm_edu/accounts.ex (扩展现有)
defmodule TcmEdu.Accounts do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource TcmEdu.Accounts.User do
      rpc_action :list_users, :read
      rpc_action :list_students, :list_students
      rpc_action :list_teachers, :list_teachers
      rpc_action :list_admins, :list_admins
      rpc_action :create_user, :register_with_role
      rpc_action :update_user, :update
      rpc_action :change_password, :change_password
    end
  end

  resources do
    resource TcmEdu.Accounts.User
    resource TcmEdu.Accounts.Token
  end
end

# lib/tcm_edu/courses.ex
defmodule TcmEdu.Courses do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource TcmEdu.Courses.Course do
      rpc_action :list_courses, :read
      rpc_action :list_published_courses, :list_published
      rpc_action :list_popular_courses, :list_popular
      rpc_action :create_course, :create_course
      rpc_action :update_course, :update
      rpc_action :publish_course, :publish
      rpc_action :archive_course, :archive
      rpc_action :delete_course, :destroy
    end

    resource TcmEdu.Courses.CourseCategory do
      rpc_action :list_categories, :read
      rpc_action :create_category, :create
    end

    resource TcmEdu.Courses.Chapter do
      rpc_action :list_chapters, :read
      rpc_action :create_chapter, :create
    end

    resource TcmEdu.Courses.Lesson do
      rpc_action :list_lessons, :read
      rpc_action :create_lesson, :create
    end
  end

  resources do
    resource TcmEdu.Courses.Course
    resource TcmEdu.Courses.CourseCategory
    resource TcmEdu.Courses.Chapter
    resource TcmEdu.Courses.Lesson
  end
end

# lib/tcm_edu/enrollment.ex
defmodule TcmEdu.Enrollment do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource TcmEdu.Enrollment.Enrollment do
      rpc_action :my_enrollments, :read
      rpc_action :enroll_in_course, :enroll
      rpc_action :cancel_enrollment, :update
    end

    resource TcmEdu.Enrollment.Progress do
      rpc_action :update_progress, :update
    end
  end

  resources do
    resource TcmEdu.Enrollment.Enrollment
    resource TcmEdu.Enrollment.Progress
  end
end
```

---

## 7. 认证与会话管理

### 7.1 三种登录入口

```
┌──────────────────────────────────────────────────────────────┐
│ 1. 超管登录 (POST /api/auth/super_admin_sign_in)              │
│    email + password → 校验 public.super_admins                │
│    返回 JWT { sub, tenant: "public", role: :super_admin }      │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ 2. 租户用户登录 (POST /api/auth/sign_in)                        │
│    { email, password, organization_slug }                     │
│    → 根据 slug 定位 tenant schema                              │
│    → 校验该 schema 的 users 表                                 │
│    返回 JWT { sub, tenant: "tenant_<slug>", role: :... }       │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ 3. 学生登录（公开页） (POST /api/auth/student_sign_in)         │
│    同 #2，但前端根据域名（公开站 vs 子域名）自动选择            │
└──────────────────────────────────────────────────────────────┘
```

### 7.2 自定义 JWT Payload

AshAuthentication 默认 JWT 已包含 `sub`（subject = `user?id=<uuid>`），需要扩展加入 `tenant` 和 `role`：

**方案 A**：扩展 Token 资源（推荐）

```elixir
defmodule TcmEdu.Accounts.Token do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.TokenResource]

  # ... 现有实现

  # 自定义 token 生成：在 generate 钩子中加入 tenant/role
  def generate(user, purpose, opts) do
    tenant = Ash.Query.get_context(opts[:query] || user.__metadata__.query, :tenant) || "public"
    role = user.role || :super_admin
    # 调用父类实现并附加 claims
    super
    |> ...
    |> add_claim(:tenant, tenant)
    |> add_claim(:role, role)
  end
end
```

> **实际方案**：在 `AshAuthentication.Jwt.token_for_user/2` 后包装一层，添加 claim。

**方案 B**：在 Plug 解析后再补查 tenant

Plug 在解析 JWT 后发现没有 `tenant`，用 `sub` 中的 user_id 反查 organization。

→ **v1 采用方案 A**（更高效、token 自包含）。

### 7.3 登出

复用现有 `AshAuthentication.Actions.SignOut`（kg-edu 验证可行）。

---

## 8. 前端架构

### 8.1 三个独立应用（pnpm workspaces monorepo）

```
frontend-monorepo/                         # 替代现有 frontend/
├── pnpm-workspace.yaml
├── package.json
├── apps/
│   ├── admin/                             # 管理端 (Antd)
│   │   ├── next.config.mjs                # 代理 /api → :4011
│   │   ├── app/
│   │   │   ├── layout.tsx                 # AntdProvider + 布局
│   │   │   ├── login/page.tsx             # 登录页（超管 / 租户管理员）
│   │   │   ├── (dashboard)/
│   │   │   │   ├── layout.tsx             # ProLayout
│   │   │   │   ├── page.tsx               # 工作台
│   │   │   │   ├── tenants/page.tsx       # 租户管理（仅超管）
│   │   │   │   ├── users/page.tsx         # 用户管理
│   │   │   │   ├── courses/page.tsx       # 课程管理
│   │   │   │   └── settings/page.tsx
│   │   ├── lib/
│   │   │   ├── auth-context.tsx
│   │   │   └── rpc-client.ts
│   │   └── package.json
│   │
│   ├── teacher/                           # 教师端 (Antd)
│   │   ├── app/
│   │   │   ├── login/
│   │   │   ├── layout.tsx                 # 教师专属 ProLayout
│   │   │   ├── courses/                   # 我的课程
│   │   │   ├── courses/[id]/edit/         # 课程编辑（章节、课时）
│   │   │   ├── students/                  # 我的学生
│   │   │   └── profile/
│   │   └── package.json
│   │
│   └── student/                           # 学生端 (React + Tailwind)
│       ├── app/
│       │   ├── layout.tsx                 # 公开站布局
│       │   ├── page.tsx                   # 首页（轮播 + 分类 + 热门课程）
│       │   ├── courses/page.tsx           # 课程列表
│       │   ├── courses/[id]/page.tsx      # 课程详情
│       │   ├── learn/[courseId]/[lessonId]/page.tsx
│       │   ├── login/
│       │   └── my-learning/page.tsx
│       └── package.json
│
├── packages/
│   ├── rpc-client/                        # 生成的 ash_typescript 客户端
│   │   ├── src/
│   │   │   ├── ash_rpc.ts                 # mix ash_typescript.codegen 输出
│   │   │   ├── ash_types.ts
│   │   │   └── index.ts                   # 三个 app 共用
│   │   └── package.json
│   ├── ui-admin/                          # 管理/教师端共享 Antd 组件
│   │   ├── src/
│   │   │   ├── DataTable.tsx
│   │   │   ├── FormDrawer.tsx
│   │   │   ├── ProLayout.tsx
│   │   │   └── ...
│   │   └── package.json
│   └── config/                            # 共享 tsconfig/eslint
│       ├── tsconfig.base.json
│       └── eslint.config.mjs
```

### 8.2 `pnpm-workspace.yaml`

```yaml
packages:
  - 'apps/*'
  - 'packages/*'
```

### 8.3 端口分配

| App | 端口 | 后端 RPC 端点 |
|-----|------|----------------|
| admin | 3002 | `http://localhost:4011/api/rpc/run` |
| teacher | 3003 | 同上 |
| student | 3001 | 同上 |
| backend (Phoenix) | 4011 | — |

### 8.4 共享 RPC Client

```bash
# 在 monorepo 根目录
mix ash_typescript.codegen \
  --output-file packages/rpc-client/src/ash_rpc.ts \
  --types-output-file packages/rpc-client/src/ash_types.ts
```

或者保留现有的 `frontend/lib/generated/` 但用 `@/` 别名引入。

### 8.5 现有 `frontend/` 的处理

| 选项 | 说明 |
|------|------|
| **A. 整体迁移到 `frontend-monorepo/apps/student/`** | 学生端基本保持不变，迁移成本低 |
| **B. 保留 `frontend/`，新建 `frontend-admin/` 和 `frontend-teacher/`** | 简单但不够工程化 |
| → **推荐 A**，但分阶段实施：先把 student/ 迁过去，再加 admin/ 和 teacher/ |

---

## 9. UI 设计规范

### 9.1 设计原则

| 端 | 风格 | 主要组件库 | 字体 |
|----|------|------------|------|
| 管理端 | 专业、表格密集、信息层次分明 | Antd 5 + Antd Pro Components | -apple-system |
| 教师端 | 同上，但更轻量 | Antd 5（不强制用 Pro） | -apple-system |
| 学生端 | 现代、温暖、文化感、转化率高 | Tailwind 4 + 自定义 React 组件 | "Noto Serif SC"（中文衬线，体现中医文化） |

### 9.2 学生端首页设计（参考 renminyixue.com）

```
┌─────────────────────────────────────────────────────────────────┐
│  [Logo 中医教学]      首页  课程  名师  关于我们     [登录/注册]   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ╔═══════════════════════════════════════════════════════╗    │
│   ║    全屏 Banner 轮播（中医文化主题）                   ║    │
│   ║    - 黄帝内经精讲 / 针灸推拿入门 / 中医临床实操        ║    │
│   ╚═══════════════════════════════════════════════════════╝    │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│   课程分类（圆角卡片网格）                                       │
│   ┌──────┬──────┬──────┬──────┬──────┬──────┐                  │
│   │ 中医 │ 针灸 │ 推拿 │ 中药 │ 方剂 │ 临床 │                  │
│   │ 基础 │  11  │  22  │  33  │  44  │  55  │                  │
│   └──────┴──────┴──────┴──────┴──────┴──────┘                  │
├─────────────────────────────────────────────────────────────────┤
│   热门课程（横向滚动）                                           │
│   ┌─────────────┬─────────────┬─────────────┐                  │
│   │   封面图    │   封面图    │   封面图    │                  │
│   │ 中医诊断学 │ 中药学入门  │ 针灸学      │                  │
│   │ ★★★★☆ 4.8  │ ★★★★★ 5.0  │ ★★★★☆ 4.6  │                  │
│   │ 1200 人在学 │ 980 人在学  │ 750 人在学  │                  │
│   │ 李教授    │ 王教授     │ 张教授      │                  │
│   └─────────────┴─────────────┴─────────────┘                  │
├─────────────────────────────────────────────────────────────────┤
│   名师推荐                                                      │
│   ┌──────┬──────┬──────┬──────┐                                │
│   │ 头像 │ 头像 │ 头像 │ 头像 │                                 │
│   │ 简介 │ 简介 │ 简介 │ 简介 │                                 │
│   └──────┴──────┴──────┴──────┘                                │
├─────────────────────────────────────────────────────────────────┤
│   学习路径（特色模块）                                            │
│   中医入门 → 中医基础理论 → 中医诊断学 → 中医内科学              │
├─────────────────────────────────────────────────────────────────┤
│   数据展示：累计学员 10万+ / 课程 500+ / 名师 50+                │
├─────────────────────────────────────────────────────────────────┤
│   Footer                                                        │
└─────────────────────────────────────────────────────────────────┘
```

**视觉关键词**：

- **品牌色**：朱红 `#B83A2E`（中医传统色）+ 米黄 `#F4E9D8`（宣纸色）
- **点缀**：墨黑 `#2C2C2C`、竹青 `#5A7D65`
- **字体**：标题用思源宋体/Noto Serif SC（中医经典感），正文用思源黑体
- **图像**：水墨画、药材照片、太极/阴阳图作为装饰元素
- **动效**：克制，hover 时 scale(1.02) + shadow 提升

### 9.3 学生端课程列表页

```
┌───────────────────────────────────────────────────────────────┐
│  课程                                                          │
├──────────────┬────────────────────────────────────────────────┤
│              │  [搜索框]  [分类筛选] [排序：最新/最热/评分]   │
│  课程分类     │  ┌────────┬────────┬────────┬────────┐         │
│  □ 中医基础   │  │ 卡片  │ 卡片  │ 卡片  │ 卡片  │           │
│  □ 中药学     │  │       │       │       │       │           │
│  □ 方剂学     │  └────────┴────────┴────────┴────────┘         │
│  □ 临床各科   │  ┌────────┬────────┬────────┬────────┐         │
│  □ 针灸推拿   │  │ 卡片  │ 卡片  │ 卡片  │ 卡片  │           │
│              │  │       │       │       │       │           │
│  难度        │  └────────┴────────┴────────┴────────┘         │
│  □ 初级       │                                                │
│  □ 中级       │  [上一页] 1 2 3 ... 10 [下一页]                │
│  □ 高级       │                                                │
└──────────────┴────────────────────────────────────────────────┘
```

**课程卡片字段**：封面图、标题、副标题、教师头像+姓名、⭐ 评分、学习人数、课时数、是否免费、CTA 按钮

### 9.4 学生端课程详情页

```
┌───────────────────────────────────────────────────────────────┐
│  首页 / 课程 / 中医诊断学                                       │
├───────────────────────────────────────────────────────────────┤
│  ┌──────────────────────┐  课程标题                            │
│  │                      │  副标题                              │
│  │   课程封面（大图）    │  教师：XXX 主任医师                  │
│  │                      │  ⭐ 4.8 (320 评价) | 1200 人在学      │
│  └──────────────────────┘  📚 36 课时 | ⏱ 12 小时             │
│                            🏷 中医基础 / 初级 / 免费           │
│                                                               │
│                            [立即学习] (大按钮，朱红色)         │
├───────────────────────────────────────────────────────────────┤
│  [课程介绍] [章节列表] [讲师介绍] [学员评价]                    │
│  ─────────                                                   │
│  课程介绍：                                                   │
│  ...                                                          │
│  章节列表：                                                   │
│  第1章 中医诊断学概述 (3 课时)                                 │
│    课时1.1  什么是中医诊断                  [免费试听]          │
│    课时1.2  诊断的基本原理                                   │
│    课时1.3  学习方法建议                                     │
│  第2章 望诊 (5 课时)                                          │
│    ...                                                        │
└───────────────────────────────────────────────────────────────┘
```

### 9.5 管理端首页（超管 vs 租户管理员）

**超管首页**：

```
┌───────────────────────────────────────────────────────────────┐
│ [ProLayout: 顶部 logo + 租户切换 + 用户菜单]                    │
├──────────┬────────────────────────────────────────────────────┤
│ 工作台   │  平台总览                                          │
│ 租户管理 │  ┌──────┬──────┬──────┬──────┐                    │
│ 用户管理 │  │ 租户 │ 用户 │ 课程 │ 课时 │                     │
│ 课程审核 │  │  25  │ 8000 │  350 │ 4200 │                     │
│ 系统设置 │  └──────┴──────┴──────┴──────┘                    │
│          │                                                    │
│          │  最近 7 天活跃（图表）                               │
│          │  最近创建的租户（表格）                               │
└──────────┴────────────────────────────────────────────────────┘
```

**租户管理员首页**：

```
┌───────────────────────────────────────────────────────────────┐
│ [ProLayout: 顶部 logo + 用户菜单]                              │
├──────────┬────────────────────────────────────────────────────┤
│ 工作台   │  本租户概览                                          │
│ 用户管理 │  ┌──────┬──────┬──────┬──────┐                    │
│ 教师管理 │  │ 教师 │ 学生 │ 课程 │ 报名 │                     │
│ 课程管理 │  │  15  │ 800  │  60  │ 1200 │                     │
│ 班级管理 │  └──────┴──────┴──────┴──────┘                    │
│ 数据统计 │                                                    │
│          │  最近活动                                           │
└──────────┴────────────────────────────────────────────────────┘
```

### 9.6 教师端首页

```
┌───────────────────────────────────────────────────────────────┐
│ [简洁布局: 顶部 logo + 课程管理 + 我的]                          │
├─────────────────────────────────────────────────────────────────┤
│  我的课程概览                                                  │
│  ┌──────┬──────┬──────┬──────┐                                │
│  │ 全部 │ 草稿 │ 已发布│ 已下架│                                │
│  │  12  │  3   │  8   │  1   │                                │
│  └──────┴──────┴──────┴──────┘                                │
│                                                                │
│  我的课程列表 [+ 创建课程]                                      │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ 课程名 │ 状态 │ 学员 │ 课时 │ 操作                        │ │
│  │ 中医诊断 │ 已发布 │ 320 │ 36 │ [编辑] [学员] [下架]     │ │
│  │ 中药学   │ 草稿   │ 0   │ 12 │ [继续编辑] [删除]       │ │
│  └──────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────┘
```

---

## 10. 分阶段开发计划

> 详见 [`tcm-edu-progress.md`](./tcm-edu-progress.md) 的 checklist。**先 review 文档再开工**。

| Phase | 名称 | 工期估计 | 关键产出 | 优先级 |
|-------|------|----------|----------|--------|
| **0** | 文档与方案评审 | 0.5 天 | 本文档 + 进度文档 | ⬅️ 当前 |
| **1** | 多租户基础设施 | 2-3 天 | `Organization` 资源 + TenantProvisioning + 双轨迁移 + tenant_default 自动创建 | 🔴 P0 |
| **2** | 认证与超管体系 | 2 天 | `SuperAdmin` 资源 + JWT 含 tenant claim + `SetTenantFromToken` plug + 三种登录入口 | 🔴 P0 |
| **3** | 重构 `User` + 角色扩展 | 1-2 天 | 现有 User 改为多租户 + 角色 `[:tenant_admin, :teacher, :student]` + 权限策略 | 🔴 P0 |
| **4** | 超管 Console（管理端骨架） | 3-4 天 | Monorepo 初始化 + admin app + 登录页 + 租户管理 CRUD + 用户管理（跨租户） | 🔴 P0 |
| **5** | 教师 Console | 2-3 天 | teacher app + 我的课程列表 + 课程创建/编辑（章节/课时） | 🟡 P1 |
| **6** | 课程域 | 2-3 天 | `Course`/`Chapter`/`Lesson`/`CourseCategory` 资源 + AshAdmin 集成 + 测试数据 | 🟡 P1 |
| **7** | 选课与进度 | 2 天 | `Enrollment`/`Progress` 资源 + 选课流程 + 进度上报 | 🟢 P2 |
| **8** | 学生端首页 | 3-4 天 | student app 首页（banner + 分类 + 热门课程 + 名师） | 🟡 P1 |
| **9** | 学生端课程列表 + 详情 | 3-4 天 | 列表页 + 详情页 + 选课按钮 + 章节展开 | 🟡 P1 |
| **10** | 集成打磨 | 2-3 天 | 跨端联调 + 错误处理 + Loading + 空状态 + SEO | 🟢 P2 |
| **11** | 部署与文档 | 1-2 天 | Dockerfile + docker-compose + 部署文档 + 运维手册 | 🟢 P2 |

**总计**：~22-30 工作日（单人）或 ~10-15 工作日（3 人小团队）

### 10.1 Phase 0 详情（当前）

**目标**：完成方案文档 + 用户 review

**交付物**：
- ✅ `docs/tcm-edu-dev-plan.md`（本文件）
- ✅ `docs/tcm-edu-progress.md`（进度跟踪）
- ⏳ 用户 review + 反馈
- ⏳ 开放问题决策（见 §13）

### 10.2 Phase 1 详情（多租户基础设施）

**目标**：让系统支持多租户 + 可创建租户

**任务清单**：
- [ ] 创建 `TcmEdu.System` 域和 `Organization` 资源
- [ ] 配置 `manage_tenant` 块（schema 命名）
- [ ] 实现 `Ash.ToTenant` protocol
- [ ] 创建 `priv/repo/tenant_migrations/` 目录
- [ ] 写初始租户迁移（用户表骨架，可后续完善）
- [ ] 实现 `TcmEdu.TenantProvisioning`（建 schema + 跑迁移 + 创建初始 admin）
- [ ] 自定义 mix 任务 `mix tcm_edu.migrate`
- [ ] 编写测试：创建/删除租户的 round-trip

**完成标志**：
- `mix tcm_edu.migrate` 可成功执行
- 通过 RPC 创建租户后，`pg_namespace` 中能看到 `tenant_<slug>`
- 该租户的 `users` 表存在且为空
- 删除租户后 schema 被 CASCADE 删除

### 10.3 Phase 2 详情（认证与超管）

**目标**：超管能登录、能创建租户

**任务清单**：
- [ ] 创建 `TcmEdu.System.SuperAdmin` 资源
- [ ] 自定义 JWT signer 注入 `tenant`/`role` claims
- [ ] 实现 `TcmEduWeb.Plugs.SetTenantFromToken`
- [ ] 配置 router 的 `:api_auth` pipeline 接入新 plug
- [ ] 扩展 `AuthController`：
  - [ ] `super_admin_sign_in` action
  - [ ] `sign_in_with_org` action（接受 `organization_slug`）
  - [ ] `me` action（返回当前 actor + tenant 信息）
- [ ] 测试三种登录

**完成标志**：
- 三个登录流程能拿到有效 JWT
- JWT payload 包含 `tenant` + `role`
- 携带 JWT 的请求能正确解析 actor

### 10.4 Phase 3 详情（User 重构）

**目标**：User 资源支持多租户 + 三种角色

**任务清单**：
- [ ] 重写 `TcmEdu.Accounts.User` 加 `multitenancy :context`
- [ ] 改 `role` 约束 `[:tenant_admin, :teacher, :student]`
- [ ] 添加 `status` 字段
- [ ] 重写 policies
- [ ] 编写租户迁移：`priv/repo/tenant_migrations/<ts>_create_tenant_users.exs`
- [ ] 把现有 `users` 数据迁移到 `tenant_default`
- [ ] 写测试

**完成标志**：
- 现有 admin/user 数据保留在 `tenant_default` schema
- 注册新用户时需要传 `organization_slug`
- `list_users` 只能看到本租户用户

### 10.5 Phase 4 详情（超管 Console）

**目标**：超管能登录、能管理租户和用户

**任务清单**：
- [ ] 初始化 `frontend-monorepo/` pnpm workspace
- [ ] 迁移现有 `frontend/` → `apps/student/`（保留现有 demo 资源，先不删除）
- [ ] 新建 `apps/admin/`：Next.js + Antd + ProLayout
- [ ] 配置 Next.js 代理 `/api/*` → `:4011`
- [ ] 实现登录页（区分超管/租户管理员两种登录入口）
- [ ] 实现 ProLayout + 路由守卫
- [ ] **租户管理页**：列表 + 创建 + 编辑 + 删除
- [ ] **用户管理页**：选择租户 → 列表用户 + 创建 + 编辑角色 + 删除
- [ ] **工作台**：平台总览（图表 + 数字）

**完成标志**：
- 超管登录后能看到所有租户、能在 UI 上创建租户
- 进入某租户后能看到/管理其用户

### 10.6 Phase 5-6 详情（教师 Console + 课程域）

**目标**：教师能创建/发布课程

**任务清单**：
- [ ] 创建 `Course`/`Chapter`/`Lesson`/`CourseCategory` 资源
- [ ] 写租户迁移
- [ ] 接入 `AshAdmin.Resource`（可选，自动生成 `/admin/courses` 路由）
- [ ] 新建 `apps/teacher/`：Next.js + Antd
- [ ] 教师登录 → 课程列表页（我的课程）
- [ ] 课程编辑器：基本信息 + 章节管理 + 课时管理
- [ ] 课程发布流程
- [ ] 课程分类管理（管理员可见）

**完成标志**：
- 教师能在 UI 上创建课程、添加章节、添加课时
- 课程发布后能通过 API 查询到

### 10.7 Phase 7 详情（选课与进度）

**任务清单**：
- [ ] 创建 `Enrollment`/`Progress` 资源
- [ ] 写租户迁移
- [ ] 实现 `enroll` action（含唯一性校验）
- [ ] 实现进度上报 API（前端视频播放器定期调用）

### 10.8 Phase 8-9 详情（学生端）

**任务清单**：
- [ ] 设计学生端 UI 组件库（参考 §9.2）
- [ ] 实现首页：banner + 分类 + 热门课程 + 名师
- [ ] 实现课程列表页
- [ ] 实现课程详情页
- [ ] 实现"立即学习"流程（未登录 → 注册/登录 → 选课 → 学习）

### 10.9 Phase 10-11 详情（集成 + 部署）

**任务清单**：
- [ ] 错误处理统一（Ash 错误 → 前端友好提示）
- [ ] Loading 骨架屏
- [ ] SEO meta tags
- [ ] Dockerfile（多阶段构建）
- [ ] docker-compose.yml
- [ ] 部署文档

---

## 11. 测试与质量保证

### 11.1 后端测试

| 测试类型 | 工具 | 覆盖 |
|----------|------|------|
| 单元测试（资源 actions） | ExUnit + Ash.Test | 每个 resource action |
| 集成测试（多租户隔离） | ExUnit | 跨租户访问被禁止 |
| 认证测试 | ExUnit | 三种登录 + JWT 解析 |
| 迁移测试 | mix ecto.migrate | 双向迁移 |
| RPC 烟测 | curl 脚本 | `lib/tcm_edu/scripts/smoke_test.exs` 已存在 |

### 11.2 前端测试

| 测试类型 | 工具 | 覆盖 |
|----------|------|------|
| 组件测试 | Vitest + Testing Library | 关键组件 |
| E2E | Playwright | 登录、创建租户、创建课程、选课 |
| 类型检查 | `tsc --noEmit` | 整个 monorepo |

### 11.3 测试数据

- 用 `mix tcm_edu.seed_dev` 创建测试租户和用户
- 固定账号：`super@admin.com / password123`（超管）
- 固定账号：`alice@tenant-default.com / password123`（租户管理员）
- 固定账号：`bob@tenant-default.com / password123`（教师）
- 固定账号：`charlie@tenant-default.com / password123`（学生）

---

## 12. 部署与运维

### 12.1 开发环境（已有）

```bash
# 现有 dev.sh 类似
bin/herdr-services.sh start        # Phoenix :4011 + Next.js :3001
```

### 12.2 多前端开发环境

```bash
# 在 frontend-monorepo 根目录
pnpm dev                            # 并行启动三个 Next.js app
# 或者：
pnpm --filter student dev           # :3001
pnpm --filter admin dev             # :3002
pnpm --filter teacher dev           # :3003
```

需要在 `bin/herdr-services.sh` 中扩展为 5 个 pane。

### 12.3 生产部署

```
                     ┌──────────┐
                     │   Nginx  │
                     └────┬─────┘
                          │
       ┌──────────────────┼──────────────────┐
       │                  │                  │
   /admin/*          /teacher/*          /student/*
   /app/admin/       /app/teacher/       /app/student/    /api/*
       │                  │                  │              │
       ▼                  ▼                  ▼              ▼
   ┌────────┐         ┌────────┐        ┌────────┐     ┌────────┐
   │ admin  │         │teacher │        │student │     │Phoenix │
   │ static │         │ static │        │ static │     │  :4011 │
   └────────┘         └────────┘        └────────┘     └────────┘
                                                                │
                                                                ▼
                                                          ┌──────────┐
                                                          │ Postgres │
                                                          └──────────┘
```

- 三个 Next.js 静态导出（`out/`）
- Phoenix 用 `Plug.Static` 服务静态文件
- 一个 Nginx 路由分发
- Docker compose 编排

### 12.4 监控

- Sentry（前后端错误）
- Oban Web（查看后台任务）
- pg_stat_statements（慢查询）
- Phoenix LiveDashboard（dev）

---

## 13. 风险与开放问题

### 13.1 待确认决策点（请用户 review）

| # | 决策点 | 建议方案 | 备选 |
|---|--------|----------|------|
| Q1 | super_admin 存储位置？ | `public.super_admins` 独立表 | `tenant_default` 中的 User（kg-edu 风格） |
| Q2 | 默认租户名？ | `tenant_default` | 删除默认租户，首次创建租户时强制指定 |
| Q3 | JWT 中 `tenant` claim？ | ✅ 是（推荐） | ❌ 否，每次从 DB 查 |
| Q4 | 是否需要 AshAdmin 自动生成 admin UI？ | ✅ 是（节省 CRUD 工作） | ❌ 否，全部手写 |
| Q5 | Monorepo 工具？ | **pnpm workspaces**（与现有 pnpm 兼容） | Turborepo + pnpm |
| Q6 | 现有 `frontend/` 怎么处理？ | 迁移到 `apps/student/`，**Todo/Post/Chat demo 资源保留但隐藏** | 整体删除 demo，重写 |
| Q7 | 是否支持付费课程？ | ❌ v1 全部免费 | ✅ 接入支付（v2） |
| Q8 | 课时类型支持？ | 视频 + 文章 + PDF（v1） | 仅视频（v1） |
| Q9 | 是否支持课程评价？ | ❌ v1 不做 | ✅ v1 做 |
| Q10 | 多语言？ | ❌ v1 仅中文 | ✅ v1 中英双语 |
| Q11 | 部署目标？ | Docker（参考 kg-edu） | Kubernetes |
| Q12 | 现有 Chat/Storage/Agents 是否保留？ | ✅ 保留（v1 不开放给学生，作为内部资源） | ❌ 删除 |

### 13.2 已知风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| Ash 多租户 API 在 `Ash.ToTenant` 实现细节上可能有坑 | 跨租户访问泄露 | 写严格的 policy + 集成测试 |
| 自定义 JWT claim 可能与 AshAuthentication 默认行为冲突 | 登录失败 | 参考 kg-edu 已有方案 |
| 现有 Todo/Post 资源与新设计不兼容 | 数据丢失 | 迁移到 `tenant_default` 而不是删除 |
| Next.js 16 monorepo 工具链成熟度 | 构建慢、坑多 | 备选 Vite 替代 |
| Antd v5 + Next.js 16 兼容 | 警告/报错 | 用 `@ant-design/nextjs-registry` |
| 三个 app 共享 RPC client 版本同步 | type drift | 用 workspace 强制共享依赖 |

### 13.3 暂不做（v1 不实现）

- 直播课程
- 作业/考试
- 学习证书
- 积分/勋章
- 评论/讨论区
- 搜索（v1 用 SQL LIKE，v2 接 ES/Meilisearch）
- 微信小程序
- 移动端 App
- 支付

---

## 14. 附录：参考资料

### 14.1 关键源文件（kg-edu 参考实现）

| 文件 | 行数参考 | 说明 |
|------|----------|------|
| `/Users/bai/projects/kg-edu/backend/kg_edu/lib/kg_edu/accounts/organization.ex` | ~600 行 | 完整的 Organization 资源，含 manage_tenant、统计 action |
| `/Users/bai/projects/kg-edu/backend/kg_edu/lib/kg_edu/accounts/user.ex` | ~900 行 | User 资源，多租户 + 多角色 + 自定义 actions |
| `/Users/bai/projects/kg-edu/backend/kg_edu/lib/kg_edu/ash_migration_manager.ex` | ~200 行 | 双轨迁移管理 |
| `/Users/bai/projects/kg-edu/backend/kg_edu/lib/kg_edu/tenant_manager.ex` | ~70 行 | 跨租户操作工具 |
| `/Users/bai/projects/kg-edu/backend/kg_edu/lib/kg_edu_web/plug/set_tenant_from_token.ex` | ~120 行 | JWT → tenant 解析 plug |

### 14.2 关键文档

- [Ash Framework](https://hexdocs.pm/ash) - 框架核心
- [AshPostgres 多租户](https://hexdocs.pm/ash_postgres/multitenancy.html)
- [AshAuthentication 自定义 token](https://hexdocs.pm/ash_authentication)
- [AshTypescript](https://hexdocs.pm/ash_typescript)
- [AshAdmin](https://hexdocs.pm/ash_admin) - 自动生成 admin UI
- [Phoenix 1.8 router](https://hexdocs.pm/phoenix/Phoenix.Router.html)

### 14.3 UI 参考

- https://www.renminyixue.com - 人民医学网（首页 + 课程列表）
- https://ant.design/ - Antd 设计规范
- https://gw.alipayobjects.com/os/lib/antd/5.x/ - Antd 5 文档
- https://lucide.dev - 图标库（Antd 自带一部分）

---

## 📋 Review 清单（用户）

在开始 Phase 1 之前，请确认：

- [ ] 已读完整文档
- [ ] §13.1 中 12 个 Q 已给出答案
- [ ] §10 的 11 个 phase 工期估计合理
- [ ] §9 的 UI 设计方向（特别是学生端）符合预期
- [ ] §3.2 的 schema 命名（`tenant_<slug>`）可接受
- [ ] §6.1.1 的 Organization 字段足够/可调整
- [ ] §8.1 的 monorepo 结构可接受
- [ ] §8.5 关于现有 `frontend/` 处理方案已确认

确认后即可进入 Phase 1。