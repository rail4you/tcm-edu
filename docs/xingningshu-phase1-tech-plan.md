# 杏宁树 · 第一期技术开发方案

> **版本**：V1.1
> **编制日期**：2026-07-22
> **平台**：杏宁树（智能医学教育综合在线平台）
> **仓库**：`/Users/bai/projects/tcm-edu`
> **阶段划分**：
> - **第一期（本方案重点）**：移动 Web（PWA）+ 安卓 APP + 现有架构可落地功能 + **AI 文本（qwen flash）** + **医学图片生成**
> - **第二期（仅作范围预告，本方案不展开）**：iOS APP + 3D/VR + AR + 实时语音（Omni Realtime）+ 数字人 + 医学短视频生成 + 知识图谱 + SP 模拟 + 支付等
> **当前状态**：仅规划，**不开发**
>
> **第一期 AI 模型定稿**：
> - 文本主力：**`qwen-flash`**（快、便宜、131k 上下文）
> - 多模态兜底 / 视觉：`qwen3-vl-flash`（文本+图片）；更强用 `qwen-plus`
> - 复杂推理：`deepseek-v4-flash`
> - 医学图片生成：`wanx2.1-t2i-turbo`（文生图 / 解剖示意图）
>
> **凭证与资源沿用 `kg-edu`**：Qwen API Key、阿里云 OSS bucket 均直接复用（见 §8.0）
> **原始方案遗留**：`docs/xingningshu-v2-dev-plan.md`（合同对齐版，含 18 周甘特）

---

## 0. 读这份文档前

本文档遵循三个原则：

1. **架构先行**：先盘点现有仓库能做什么，再决定第一期做什么
2. **接口边界清晰**：第一期交付物 = 当前 Ash 资源 + Next.js 前端 + Capacitor 安卓壳，不引入新的中间件
3. **第二期延后**：合同中所有"硬骨头"统一推后，不在本期方案展开细节

---

## 1. 现状盘点（当前架构能力清单）

### 1.1 后端（Phoenix 1.8 + Elixir 1.18）

| 模块 | 现有资源 | 状态 | 第一期能否直接用 |
|------|----------|------|------------------|
| `TcmEdu.Accounts` | `User` / `Role` / `Permission` / `RolePermission` / `UserRole` / `UserPermission` / `Token` | ✅ 已实现 | ✅ 直接用 |
| `TcmEdu.System` | `Organization`（多租户目录） + `SuperAdmin` | ✅ 已实现 | ✅ 直接用 |
| `TcmEdu.Courses` | `Course` / `Chapter` / `Lesson` / `CourseCategory` | ✅ 已实现 | ✅ 直接用 |
| `TcmEdu.Enrollment` | `Enrollment`（选课） + `Progress`（学习进度） | ✅ 已实现 | ✅ 直接用 |
| `TcmEdu.Chat` | `ChatSession` / `ChatMessage` / `ChatTask` | ✅ 已实现 | ✅ 直接用 |
| `TcmEdu.Storage` | `Attachment` / `Blob` | ✅ 已实现 | ✅ 直接用 |
| `TcmEdu.Agents` | `QuizAgent` / `BgTaskAgent` / `CounterAgent` / `CallAgentAction` / `WebFetchAction` 等 12 个 | ✅ 已实现 | ✅ 直接用 |
| `TcmEdu.Workers` | `LongTaskWorker`（Oban） | ✅ 已实现 | ✅ 直接用 |
| 认证 | AshAuthentication password strategy + Bearer token + 超管登录 | ✅ 已实现 | ✅ 直接用 |
| 多租户 | schema 多租户（`tenant_<slug>`）+ `manage_tenant` 自动建库 | ✅ 已实现 | ✅ 直接用 |
| 权限 | Ash.Policy.Authorizer + 30+ 权限点 + RBAC | ✅ 已实现 | ✅ 直接用 |
| RPC | `/api/rpc/run` `/api/rpc/validate`（AshTypescript 生成） | ✅ 已实现 | ✅ 直接用 |
| Chat SSE | `/api/chat` + `/api/chat/events`（流式响应） | ✅ 已实现 | ✅ 直接用 |
| 文件上传 | `PostUploadController`（multipart → AshStorage） | ✅ 已实现 | ✅ 直接用 |
| 部署 | `Dockerfile` + `rel/` release + `deploy.sh` | ✅ 已实现 | ✅ 直接用 |
| 监控 | `db_stats_live`（LiveView 数据库统计） | ✅ 已实现 | ✅ 直接用 |

### 1.2 前端（Next.js 16 monorepo）

| 应用/包 | 现有内容 | 第一期能否直接用 |
|---------|----------|------------------|
| `apps/web`（统一 Next.js 应用，端口 3001） | 学员端 (`/`, `/courses`, `/course`, `/learn`, `/my-learning`, `/posts`, `/chat`) + 教师端 (`/teacher/*`) + 管理端 (`/admin/*`) + 登录页 (`/login`) | ✅ 直接用 |
| `apps/student` / `apps/teacher` / `apps/admin` | 空脚手架（无实际页面） | ❌ 第一期不启用，作为第二期 monorepo 拆分储备 |
| `packages/rpc-client` | `ash_rpc.ts` / `ash_types.ts` / `ash_zod.ts` + `rpcHooks.ts` + `sharedAuth.ts` | ✅ 直接用 |
| `packages/ui-admin` | Antd 封装（按需） | ✅ 直接用 |
| `packages/config` | `tsconfig.base.json` | ✅ 直接用 |
| 设计 | Tailwind 4 + Antd 5 + `@ant-design/pro-components` + `katex` + `recharts` 等 | ✅ 直接用 |
| AI 集成 | `@ai-sdk/react` + `ai` + `@assistant-ui/react` | ✅ 直接用 |

### 1.3 外部依赖（合同 §1.6.6）

| 能力 | 模型 / 服务 | 状态 | 第一期 |
|------|-------------|------|--------|
| **文本对话（主力）** | `qwen-flash` @ DashScope | ✅ Key 已就绪 | ✅ 第一期接 |
| 多模态理解（文本+图片） | `qwen-plus` @ DashScope | ✅ Key 已就绪 | ✅ 第一期接 |
| 复杂推理 / 错题解析 | `deepseek-v4-flash` @ DeepSeek | ✅ Key 已就绪 | ✅ 第一期接 |
| **医学图片生成** | `wanx2.1-t2i-turbo` @ DashScope | ✅ Key 已就绪 | ✅ 第一期接 |
| 通义千问 Qwen-Omni-Realtime（实时语音） | Qwen Omni Realtime | ❌ 未接入 | ⏸️ 第二期 |
| 医学短视频生成（文/图生视频） | `wanx2.1-t2v` / `wanx2.1-i2v` | ❌ 未接入 | ⏸️ 第二期（延续 "视频生成可缓缓"） |
| CosyVoice 语音合成 | CosyVoice | ❌ 未接入 | ⏸️ 第二期 |
| Tripo3D / 3D 生成 | Tripo3D | ❌ 未接入 | ⏸️ 第二期 |
| Three.js + WebXR | 3D / VR | ❌ 未引入 | ⏸️ 第二期 |
| AR 解剖 | AR 眼镜 / 移动 AR | ❌ 未引入 | ⏸️ 第二期 |

> **决策**：视频生成 / 3D / VR / AR / 实时语音 / 数字人 均**缓到第二期**；第一期用"**医学图片生成**"（anatom 插图、病理示意图、教学配图）替代 3D 建模的展示需求。

### 1.4 部署 & 运维

| 项 | 状态 | 第一期 |
|----|------|--------|
| Docker 镜像构建 | ✅ 已有 | ✅ 沿用 |
| 服务器 `111.229.72.15` | ✅ 已有 | ✅ 沿用 |
| `deploy.sh` 一键部署 | ✅ 已有 | ✅ 沿用 |
| `restart.sh` 重启 | ✅ 已有 | ✅ 沿用 |
| `smoke_test.exs` 冒烟测试 | ✅ 已有 | ✅ 沿用 |
| **阿里云 OSS** | ✅ **复用 `kg-edu` bucket** | ✅ 第一期接（见 §8.0） |
| CDN / HTTPS | ❌ 暂未配 | ⏸️ 第二期 |

---

## 2. 第一期范围（做什么 / 不做什么）

### 2.1 ✅ 第一期做（架构能落地的）

```
A. 端
   ├─ A1. 移动 Web（响应式 Next.js + PWA 安装提示）
   ├─ A2. 安卓 APP（Capacitor 壳包 Next.js Web 应用）
   └─ A3. 现有 Web（PC 后台 / 教师端 / 管理端 / 学员端）继续完善

B. 学员核心
   ├─ B1. 注册 / 登录 / 找回密码（沿用 AshAuthentication）
   ├─ B2. 课程目录浏览（`/courses`）+ 课程详情（`/course/[id]`）+ 试看免费课时
   ├─ B3. 选课（`Enrollment` upsert）+ 我的学习（`/my-learning`）
   ├─ B4. 课时学习（`/learn/[lesson_id]`）— 视频/文章/PDF 三种类型
   ├─ B5. 学习进度心跳上报（`Progress.upsert_progress`，每 15 秒一次）
   ├─ B6. 断点续播（`Progress.last_position_seconds`）
   ├─ B7. AI 文字对话（`/chat` 沿用 Jido + Qwen 文本）
   └─ B8. 个人中心 / 资料 / 头像 / 密码修改

C. 教师核心
   ├─ C1. 教师工作台 `/teacher`（待办、班级、最近课程）
   ├─ C2. 课程管理（CRUD 课程/章节/课时）
   ├─ C3. 课时编辑器（富文本 + 视频/文件上传）
   ├─ C4. AI 备课助手（输入章节标题 → Qwen 生成教案大纲）
   ├─ C5. 题库管理（CRUD 题目，按难度 + 知识点）
   ├─ C6. 智能组卷基础版（输入：知识点 + 难度 + 数量 → Qwen 出题 → 存入题库）
   └─ C7. 学情概览（班级完成率、平均分雷达图 — 用 `recharts`）

D. 院校 / 管理端核心
   ├─ D1. 多租户管理 `/admin/organizations`（创建租户 / 启停 / 配置）
   ├─ D2. 人员管理 `/admin/users`（增删改查 + 角色分配 + 批量导入）
   ├─ D3. 课程审核 `/admin/courses`（发布/下架/置顶）
   ├─ D4. 数据驾驶舱 `/admin/dashboard`（已有 `db_stats_live`，扩 6 个核心指标）
   ├─ D5. 权限管理 `/admin/permissions`（角色 × 权限矩阵）
   └─ D6. 操作日志 `/admin/audit_logs`（新建资源）

E. 平台能力
   ├─ E1. 全文搜索（课程 / 题目 / 用户 — Postgres `tsvector`）
   ├─ E2. 通知中心（站内信 `Notification` 新资源 — Oban 异步推送）
   ├─ E3. 文件上传（已有 AshStorage，覆盖：头像、课时附件、题库配图）
   └─ E4. 多租户自助开通（`mix tcm_edu.create_tenant` + 管理端 UI）

F. AI（文本 + 医学图片）
   ├─ F1. AI 文字导师（已有 Jido Chat）— 增强：可读取学员进度做"今天学什么"建议
   ├─ F2. AI 备课助手（教师工作台）
   ├─ F3. AI 智能组卷基础（教师出题）
   ├─ F4. AI 错题解析（学员错题 → 文字解释 + 同类题推荐）
   └─ F5. AI 医学图片生成（教师输入文字 → `wanx2.1-t2i-turbo` 生成解剖图 / 病理图 / 教学配图 → OSS）
```

### 2.2 ⏸️ 第二期再做（不展开）

> **原则**：视频生成 / 3D / VR / AR / 实时语音 / 数字人 = "可缓缓"的重型能力，全部延后到第二期。
> 第一期用"**医学图片生成**"承接大部分视觉展示需求，不引入 3D 建模技术栈。

```
- iOS APP（Capacitor iOS target，等第一期安卓跑通再开）
- 微信小程序（Taro 或 H5 嵌入，二期决策）
- 医学短视频生成（wanx2.1-t2v / i2v，作为“视频生成可缓缓”的延续）
- 3D 解剖 + VR（Three.js + WebXR）
- AR 解剖助手（AR 眼镜 / 移动 AR）
- 知识图谱（Neo4j 或 PG 图存储）
- AI SP 临床模拟 + MDT 多学科会诊
- AI 生成 PPT / 自动出卷 / 自动剪辑视频
- AI 数字人讲师 / 代课
- 实时语音交互（Qwen Omni Realtime）
- AI 防作弊双机位（OSCE）
- 联邦学习 / 双活灾备
- 院校教务 / 一卡通 / 门禁 / HIS / LIS / EMR / PACS 对接
- 统一支付（微信 / 支付宝）
- 鸿蒙 / AR 眼镜 / VR 头显
- 自动化巡课摄像头
- CDN / HTTPS / 异地灾备
```

---

## 3. 技术架构（第一期定稿）

```
                          ┌─────────────────────────────┐
                          │  移动 Web（PWA）            │
                          │   Android（Capacitor 壳）    │
                          │  Next.js 16 (apps/web)      │
                          │  http://<host>:3001         │
                          └──────────────┬──────────────┘
                                         │ HTTPS / Bearer Token
                                         │ POST /api/rpc/run
                                         │ POST /api/chat (SSE)
                                         │ POST /api/posts/.../upload
                                         ▼
                          ┌─────────────────────────────┐
                          │  Phoenix 1.8                │
                          │  AshTypescript RPC + Chat   │
                          │  Oban (异步组卷 / 通知)     │
                          │  Jido Agents (AI 文字)      │
                          │  AshAuthentication          │
                          └──────────────┬──────────────┘
                                         │
                          ┌──────────────┴──────────────┐
                          ▼                             ▼
                ┌──────────────────┐         ┌──────────────────────────────┐
                │ PostgreSQL 13+   │         │ AI 服务（OpenAI 兼容）        │
                │ ├─ public        │         │ ├─ qwen-flash  文本        │
                │ ├─ tenant_default│         │ ├─ qwen-plus      多模态      │
                │ └─ tenant_*      │         │ ├─ deepseek-v4-flash 推理     │
                └──────────────────┘         │ └─ wanx2.1-t2i-turbo 图片     │
                          ▲                  └──────────────┬───────────────┘
                          │                                   │
                          │                                   ▼
                ┌─────────┴──────────┐     ┌─────────────────────────────────┐
                │ Docker release      │     │ 阿里云 OSS（复用 kg-edu bucket）│
                │ 服务器 111.229.72.15│     │ 图片 / 视频 / 附件             │
                └────────────────────┘     └─────────────────────────────────┘
```

**关键决策**：

| 决策 | 选择 | 理由 |
|------|------|------|
| 安卓壳方案 | **Capacitor 6**（不是 RN、不是 TWA） | 复用 Next.js 代码 100%，一份代码三个端；支持原生插件（推送/相机）；无需重写 UI；与现有 PWA 策略无缝衔接 |
| 移动 Web | **PWA + 响应式**（Tailwind 断点） | 与安卓壳同源代码；iOS 用户先满足；后续 iOS 端直接 Capacitor iOS target 复用 |
| AI 文本模型 | **`qwen-flash` 主力 + `deepseek-v4-flash` 推理** | 用户指定用 qwen flash（快 / 便宜）；DeepSeek 分担错题解析等复杂推理 |
| 多模态/视觉兜底 | **`qwen3-vl-flash`** | 处理带图问题（上传影像 / 图片题目）；复杂时升 `qwen-plus` |
| AI 图片生成 | **`wanx2.1-t2i-turbo`**（文生图） | 医学插图 / 解剖示意图 / 病理图 / 教学配图；替代 3D 建模【图片展示需求】 |
| 文件存储 | **阿里云 OSS（复用 `kg-edu` bucket）** | 已有凭证与 bucket，上传头像 / 附件 / AI 生成的图片都会传到 OSS |
| 通知 | **Oban + 站内信**（不接入推送） | 第一期免去 APNs/FCM 复杂度；推送统一放第二期 |
| 部署 | **Docker release 单机部署** | 现有架构已能承载百级租户；分布式部署留二期 |
| 实时 | **SSE**（已有 `/api/chat/events`） | 不引入 WebSocket 服务器；二期若需语音流再升级 |

---

## 4. Capacitor 安卓壳 — 详细设计

### 4.1 为什么选 Capacitor 而不是 RN

| 维度 | Capacitor | React Native | TWA |
|------|-----------|--------------|-----|
| 复用现有 Next.js 代码 | ✅ 100% | ❌ 0%（需重写 UI 层） | ✅ 100%（仅浏览器） |
| 上架 Google Play | ✅ 标准 APK | ✅ 标准 APK | ⚠️ 受限（数字物品链接） |
| 原生插件（推送/相机/文件系统） | ✅ 丰富 | ✅ 最丰富 | ❌ 几乎无 |
| 维护成本 | ⭐⭐⭐ 低（一套代码） | ⭐⭐ 中（双代码） | ⭐⭐⭐⭐⭐ 低 |
| iOS 复用（第二期） | ✅ 同代码换 target | ❌ 不能 | ❌ 不能 |
| 学习成本 | ⭐⭐⭐⭐ 中低 | ⭐⭐ 高 | ⭐⭐⭐⭐⭐ 低 |

**结论**：第一期要快速出安卓且不增加维护负担，Capacitor 是最优解。

### 4.2 Capacitor 6 工程结构

```
frontend-monorepo/
├── apps/
│   └── web/                     # 现有 Next.js 应用（不要改）
└── packages/
    └── android-shell/                   # 新建（独立 npm 包）
        ├── capacitor.config.ts           # 指向 apps/web 的静态导出
        ├── package.json
        ├── tsconfig.json
        ├── android/                      # 原生安卓工程（Capacitor 生成）
        ├── public/                       # PWA manifest + 图标
        └── src/
            └── plugins/                  # 自定义原生插件（可选）
```

### 4.3 Capacitor 配置（关键项）

```typescript
// packages/android-shell/capacitor.config.ts
import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.xingningshu.app',           // 应用包名（需甲方提供签名）
  appName: '杏宁树',
  webDir: '../../apps/web/out',           // Next.js 静态导出目录
  server: {
    // 生产环境：本地静态资源
    androidScheme: 'https',
    // 开发环境（如需热重载）：
    // url: 'http://10.0.2.2:3001',        // 安卓模拟器 → 宿主机
    // cleartext: true,
  },
  plugins: {
    SplashScreen: {
      launchShowDuration: 1500,
      backgroundColor: '#C97B4A',
      showSpinner: false,
    },
    StatusBar: {
      style: 'DARK',
      backgroundColor: '#2F5D50',
    },
    App: {
        // 防止安卓返回键直接退出（学员学习中误触）
        backButton: {
          exitOnBack: false,
        },
      },
  },
};
```

### 4.4 Next.js 静态导出适配

现有 `apps/web` 已配置 `output: 'export'`（待确认，无则需修改 `next.config.mjs`）。Capacitor 直接消费 `apps/web/out/` 目录。

**前置修改**：
- `apps/web/next.config.mjs`：确保 `output: 'export'` + `images.unoptimized: true`（Capacitor 不支持 Next.js image optimization）
- 所有 API 调用走 `NEXT_PUBLIC_API_BASE`（运行时注入，避免硬编码）

### 4.5 原生能力清单（第一期最小集合）

| 插件 | 用途 | 必要性 |
|------|------|--------|
| `@capacitor/app` | 安卓返回键拦截 | ✅ 必要 |
| `@capacitor/status-bar` | 状态栏配色 | ✅ 必要 |
| `@capacitor/splash-screen` | 启动画面 | ✅ 必要 |
| `@capacitor/network` | 离线检测 | ✅ 必要 |
| `@capacitor/preferences` | token / 用户偏好本地存储 | ✅ 必要（替代 localStorage，避免 WKWebView 清理） |
| `@capacitor/share` | 课程分享 | ⭕ 可选 |
| `@capacitor/haptics` | 操作反馈 | ⭕ 可选 |
| 推送（FCM） | 推送通知 | ⏸️ 第二期 |

### 4.6 安卓打包与签名

```bash
# 在 packages/android-shell 目录
pnpm install
pnpm cap add android                # 生成 android/ 工程
pnpm cap sync android               # 把 web/out 拷到 android/app/src/main/assets
pnpm cap open android               # 打开 Android Studio

# 签名
# 1. 甲方提供 keystore（或临时生成 debug keystore 给甲方验收）
# 2. android/app/build.gradle 配置 signingConfigs
# 3. ./gradlew assembleRelease → android/app/build/outputs/apk/release/app-release.apk
# 4. 甲方 Google Play 账号上架（乙方协助上传 .aab）
```

---

## 5. 后端资源增量设计（第一期新增）

> 现有资源（§1.1）已覆盖大部分功能，本节只列**新增**资源。

### 5.1 `Notification`（站内信）

```elixir
defmodule TcmEdu.Notification.Notification do
  use Ash.Resource,
    domain: TcmEdu.Notification,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypescript.Resource],
    authorizers: [Ash.Policy.Authorizer]

  multitenancy do
    strategy :context
  end

  postgres do
    table "notifications"
    repo TcmEdu.Repo
  end

  typescript do
    type_name "Notification"
  end

  attributes do
    uuid_primary_key :id
    attribute :recipient_id, :uuid, allow_nil?: false, public?: true
    attribute :actor_id, :uuid, public?: true
    attribute :type, :atom,
      constraints: [one_of: [:enrollment, :progress, :course_published, :system, :quiz_graded]],
      public?: true
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :body, :string, public?: true
    attribute :payload, :map, default: %{}, public?: true
    attribute :read_at, :utc_datetime, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :recipient, TcmEdu.Accounts.User, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :notify do
      accept [:recipient_id, :actor_id, :type, :title, :body, :payload]
    end

    update :mark_read do
      accept []
      change set_attribute(:read_at, expr(now()))
    end

    update :mark_all_read do
      # 批量：actor 维度
      require_atomic? false
      change fn changeset, _ctx ->
        actor_id = Ash.Changeset.get_actor(changeset).id
        Ash.Changeset.filter(changeset, recipient_id == ^actor_id and is_nil(read_at))
      end
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(recipient_id == ^actor(:id))
    end
    policy action_type(:create) do
      # 仅 Oban worker 调用，需绕开 actor 检查
      authorize_if actor_attribute_equals(:role, :tenant_admin)
      authorize_if actor_attribute_equals(:role, :teacher)
    end
  end
end
```

### 5.2 `AuditLog`（操作日志）

```elixir
defmodule TcmEdu.System.AuditLog do
  # 跨租户：存在 public schema
  attributes do
    uuid_primary_key :id
    attribute :tenant, :string, allow_nil?: false, public?: true
    attribute :actor_id, :uuid, public?: true
    attribute :action, :string, allow_nil?: false, public?: true   # e.g., "course.publish"
    attribute :resource_type, :string, public?: true                 # e.g., "Course"
    attribute :resource_id, :uuid, public?: true
    attribute :changes, :map, default: %{}, public?: true          # before / after diff
    attribute :ip, :string, public?: true
    attribute :user_agent, :string, public?: true
    create_timestamp :inserted_at, public?: true
  end

  actions do
    defaults [:read]
    create :record do
      accept [:tenant, :actor_id, :action, :resource_type, :resource_id, :changes, :ip, :user_agent]
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:__struct__, TcmEdu.System.SuperAdmin)
      authorize_if actor_attribute_equals(:role, :tenant_admin)
    end
  end
end
```

### 5.3 `Question` + `QuestionBank`（题库）

```elixir
defmodule TcmEdu.Quiz.Question do
  # 租户域：每个机构自己的题库
  attributes do
    uuid_primary_key :id
    attribute :bank_id, :uuid, allow_nil?: false, public?: true
    attribute :type, :atom,
      constraints: [one_of: [:single, :multi, :judge, :essay]],
      public?: true
    attribute :difficulty, :integer, default: 3, public?: true  # 1-5
    attribute :stem, :string, allow_nil?: false, public?: true
    attribute :options, {:array, :map}, default: [], public?: true  # [{label: "A", text: "...", correct: true}]
    attribute :answer, :string, public?: true
    attribute :explanation, :string, public?: true
    attribute :tags, {:array, :string}, default: [], public?: true
    attribute :knowledge_points, {:array, :string}, default: [], public?: true
  end

  relationships do
    belongs_to :bank, TcmEdu.Quiz.QuestionBank
  end

  actions do
    defaults [:read, :create, :update, :destroy]
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
    policy action_type(:read) do
      authorize_if actor_present()  # 学员可见
    end
    policy action([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:role, :tenant_admin)
      authorize_if actor_attribute_equals(:role, :teacher)
    end
  end
end
```

### 5.4 `Attempt` + `AttemptAnswer`（学员答题记录）

```elixir
defmodule TcmEdu.Quiz.Attempt do
  attributes do
    uuid_primary_key :id
    attribute :user_id, :uuid, allow_nil?: false, public?: true
    attribute :question_id, :uuid, allow_nil?: false, public?: true
    attribute :answer, :string, public?: true
    attribute :is_correct, :boolean, public?: true
    attribute :score, :decimal, public?: true
    attribute :answered_at, :utc_datetime, public?: true
    attribute :source, :atom,
      constraints: [one_of: [:practice, :exam, :homework]],
      default: :practice, public?: true
  end
  # ...
end
```

### 5.5 新域 `TcmEdu.Notification` 与 `TcmEdu.Quiz`

```
lib/tcm_edu/
├── notification/
│   ├── notification.ex
│   └── notification_domain.ex       # 新增 domain
└── quiz/
    ├── question.ex
    ├── question_bank.ex
    ├── attempt.ex
    ├── attempt_answer.ex
    └── quiz_domain.ex               # 新增 domain
```

**Domain 边界**：
- `TcmEdu.Notification` — 站内信（含 `delivered_at`、`read_at`、`channel` 字段预留，方便第二期加推送/邮件）
- `TcmEdu.Quiz` — 题库与作答记录（独立域，方便第二期叠加"试卷 / 考试"）

---

## 6. 后端 RPC 接口增量（第一期）

> 现有 `/api/rpc/run` 已覆盖所有 Ash 资源的 `code_interface`，新增资源后只需 `mix ash_typescript.codegen` 重新生成 TypeScript 类型即可。
> 本节列出**第一期新增/调整**的非标准 RPC（自定义 controller）。

### 6.1 已有

```
POST /api/rpc/run                   # 通用 RPC（AshTypescript）
POST /api/rpc/validate              # 校验（Zod schema）
POST /api/auth/sign_in              # 学员 / 教师登录
POST /api/auth/register             # 学员注册
POST /api/auth/sign_out
POST /api/auth/super_admin_sign_in  # 超管登录
GET  /api/auth/me                   # 当前用户
POST /api/chat                      # AI 对话（SSE）
GET  /api/chat/events               # 异步任务事件流
POST /api/posts/:id/upload/:name    # 文件上传
```

### 6.2 第一期新增

```
GET    /api/health                                      # 健康检查（K8s/负载均衡）
POST   /api/auth/forgot_password                        # 忘记密码（OTP 邮件 → 二期做，第一期先做"联系管理员"）
POST   /api/auth/reset_password                         # 重置
POST   /api/auth/change_password                        # 已登录改密
POST   /api/notifications/mark_all_read                 # 站内信全部已读
GET    /api/notifications/unread_count                  # 未读数（小红点）
POST   /api/progress/heartbeat                          # 学习心跳（合并进度上报，Oban 异步）
POST   /api/quiz/grade                                  # 学员提交答案 → 自动判分
POST   /api/quiz/ai_explain                             # AI 错题解析（调 Qwen）
POST   /api/ai/lesson_plan                              # AI 备课（教师输入章节 → 输出大纲）
POST   /api/ai/generate_questions                       # AI 出题（教师输入知识点 + 难度 + 数量）
GET    /api/search?q=&type=                             # 全文搜索（type=course|user|question）
POST   /api/admin/tenants                               # 超管：创建租户（绕开多租户 context）
GET    /api/admin/audit_logs                            # 操作日志列表
```

### 6.3 RPC action 清单（ash_typescript 自动生成）

新增资源后会自动暴露以下 code interface（在 Domain 模块中 `define`）：

```elixir
# TcmEdu.Notification
define :list_notifications, action: :read
define :mark_notification_read, action: :mark_read
define :mark_all_notifications_read, action: :mark_all_read
define :create_notification, action: :notify   # 仅 worker / 管理员调用

# TcmEdu.Quiz
define :list_questions, action: :read
define :create_question, action: :create
define :update_question, action: :update
define :delete_question, action: :destroy
define :submit_attempt, action: :create        # 学员提交
define :list_my_attempts, action: :read
define :ai_explain_mistake, action: :ai_explain
```

---

## 7. 前端路由与页面（第一期）

### 7.1 `apps/web/app/` 新增页面

```
apps/web/app/
├── (student)/
│   ├── page.tsx                          # 首页（学员仪表盘）
│   ├── courses/
│   │   ├── page.tsx                      # 课程列表
│   │   └── [id]/page.tsx                 # 课程详情
│   ├── learn/
│   │   └── [lesson_id]/page.tsx          # 学习页（视频/文章/PDF）
│   ├── my-learning/
│   │   ├── page.tsx                      # 我的学习
│   │   ├── mistakes/page.tsx             # 错题本
│   │   └── notifications/page.tsx        # 通知中心
│   ├── chat/
│   │   ├── page.tsx                      # AI 文字对话
│   │   └── [session_id]/page.tsx
│   ├── search/page.tsx                   # 搜索结果
│   └── profile/page.tsx                  # 个人中心
│
├── (teacher)/
│   └── teacher/
│       ├── page.tsx                      # 教师工作台
│       ├── courses/
│       │   ├── page.tsx                  # 我的课程
│       │   ├── new/page.tsx              # 新建课程
│       │   └── [id]/
│       │       ├── page.tsx              # 课程管理
│       │       ├── chapters/[cid]/lessons/[lid]/page.tsx  # 课时编辑
│       │       └── analytics/page.tsx    # 学情
│       ├── quiz/
│       │   ├── banks/page.tsx            # 题库
│       │   ├── questions/page.tsx
│       │   └── generate/page.tsx         # AI 出题
│       ├── ai/page.tsx                   # AI 备课助手
│       └── students/page.tsx             # 学员管理
│
├── (admin)/
│   └── admin/
│       ├── page.tsx                      # 数据驾驶舱
│       ├── organizations/page.tsx        # 租户管理
│       ├── users/page.tsx                # 用户管理
│       ├── courses/page.tsx              # 课程审核
│       ├── permissions/page.tsx          # 权限矩阵
│       └── audit-logs/page.tsx           # 操作日志
│
├── login/
│   ├── page.tsx                          # 学员登录
│   ├── teacher/page.tsx                  # 教师登录
│   └── admin/page.tsx                    # 超管登录
│
├── install/page.tsx                      # PWA 安装引导（移动 Web 专用）
└── manifest.json / icon-192/512          # PWA 资源
```

### 7.2 关键页面技术要点

| 页面 | 关键点 |
|------|--------|
| `/learn/[lesson_id]` | 视频用 `<video>` + `hls.js`（如课程为 HLS）；进度心跳 15s 一次；断点续播 `useEffect` 从 `Progress.last_position_seconds` |
| `/courses` | 服务端渲染（SEO）+ 客户端筛选分页 |
| `/chat` | `@assistant-ui/react` 已有，复用 |
| `/teacher/ai` | 流式输出（`@ai-sdk/react` 的 `useChat`） |
| `/admin/dashboard` | `recharts` + 6 个核心卡片 |
| `/install` | 检测 `navigator.userAgent`，给 iOS/Android 不同安装引导 |
| 全站 | Tailwind 断点 `sm/md/lg`，移动优先 |

### 7.3 移动 Web 与 PWA

```typescript
// apps/web/public/manifest.json
{
  "name": "杏宁树",
  "short_name": "杏宁树",
  "description": "智能医学教育综合在线平台",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#FFFFFF",
  "theme_color": "#2F5D50",
  "icons": [
    { "src": "/icons/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icons/icon-512.png", "sizes": "512x512", "type": "image/png" }
  ],
  "orientation": "portrait"
}
```

```typescript
// apps/web/public/sw.js （手动实现，避免 next-pwa 的复杂度）
const CACHE = 'xingningshu-v1';
const PRECACHE = ['/', '/courses', '/login', '/install'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(PRECACHE)));
});

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET' || url.pathname.startsWith('/api/')) return;
  e.respondWith(
    caches.match(e.request).then(c => c || fetch(e.request).then(r => {
      const clone = r.clone();
      caches.open(CACHE).then(cache => cache.put(e.request, clone));
      return r;
    }))
  );
});
```

---

## 8. AI 集成（第一期 — 文本 + 医学图片生成）

> 原则：图片生成进第一期，视频 / 3D / VR / AR / 实时语音 / 数字人全部缓到第二期。

### 8.0 凭证与资源（沿用以 KnowledgeHub / kg-edu 为准的共享凭证）

**Qwen / DashScope API Key（共享 key，`sk-f99eaa...`）**：

> 该 key 在 **KnowledgeHub `etc/docker/.env.production`**、kg-edu `config/runtime.exs`、
> `~/.pi/agent/models.json`(providers.qwen) 三处一致，可据此互证。
> KnowledgeHub 实际使用的模型：文本 `qwen-flash`、视觉 `qwen3-vl-flash`、更强 `qwen-plus`。

```elixir
# 读取方式一：从环境变量（推荐，不硬编码）
System.get_env("DASHSCOPE_API_KEY")   # 部署时注入
System.get_env("QWEN_BASE_URL")       # https://dashscope.aliyuncs.com/compatible-mode/v1

# 读取方式二：从 KnowledgeHub / kg-edu 约定位置读取
# ~/.pi/agent/models.json  →  providers.qwen.apiKey = "sk-f99eaa5ab16044f1a39aead070fb08e9"
# KnowledgeHub etc/docker/.env.production →  QWEN_API_KEY / QWEN_MODEL=qwen-plus
# kg-edu      config/runtime.exs →  bootstrap 用 ~/.pi/agent/models.json
```

> **⚠️ 余额提醒**：本共享 key 此前触达 DashScope 曾返回过 `402 Insufficient Balance`。
> 是否充值与配额归属需甲方确认；在余额恢复前，真实 AI 调用会失败（测试可用 mock）。

**DeepSeek API Key（来自环境变量）**：

```elixir
System.get_env("DEEPSEEK_API_KEY")    # 已在 kg-edu 运行时注入
System.get_env("DEEPSEEK_BASE_URL")   # https://api.deepseek.com/v1
```

**阿里云 OSS（复用 `kg-edu` bucket）**：

```elixir
# 来自 kg-edu config/runtime.exs、config/config.exs、config/prod.exs
config :tcm_edu, TcmEdu.Storage,   # 或在现有 Storage domain 里加 OSS adapter
  storage: TcmEdu.Storage.Aliyun,   # 参考 kg-edu 用 Waffle.Storage.AliyunOss
  bucket: "kg-edu",
  region: "cn-beijing",
  endpoint: "oss-cn-beijing.aliyuncs.com",
  access_key_id: "<OSS_ACCESS_KEY_ID>",
  access_key_secret: "<OSS_ACCESS_KEY_SECRET>"

# ⚠️ 安全：access_key_secret 不应写死进代码库，应改为环境变量
config :tcm_edu, TcmEdu.Storage,
  access_key_secret: System.get_env("OSS_ACCESS_KEY_SECRET")
```

> **key 存哪里？** kg-edu 的做法是把 provider key 存进**数据库 `api_key_configs` 表**（super admin 可运行时改，无需重启），且支持从 `~/.pi/agent/models.json` 一键兜底 seed。第一期应**沿用这套方案**：新建 `TcmEdu.System.ApiKeyConfig` 资源，避免把密钥写死在 `config/` 或 `.env`。

### 8.1 模型配置（第一期定稿）

```elixir
# config/runtime.exs (新增)
config :tcm_edu, TcmEdu.AI,
  provider: :openai_compatible,                  # Req/ReqLLM 走 OpenAI 兼容协议
  # 文本主力：qwen-flash（快 / 便宜 / 131k 上下文 / 带 reasoning）
  text_model: "qwen-flash",
  qwen_base: System.get_env("QWEN_BASE_URL") || "https://dashscope.aliyuncs.com/compatible-mode/v1",
  qwen_key: System.get_env("DASHSCOPE_API_KEY") || System.get_env("QWEN_API_KEY"),
  # 视觉理解（文本 + 图片输入）：qwen3-vl-flash（KnowledgeHub vision model）
  vision_model: "qwen3-vl-flash",
  # 更强推理（按需）：qwen-plus
  plus_model: "qwen-plus",
  # 复杂推理：deepseek-v4-flash
  reasoning_model: "deepseek-v4-flash",
  deepseek_base: "https://api.deepseek.com/v1",
  deepseek_key: System.get_env("DEEPSEEK_API_KEY"),
  # 医学图片生成（文生图）：wanx2.1-t2i-turbo
  image_model: "wanx2.1-t2i-turbo",
  timeout: 60_000
```

### 8.2 文本 Agent（第一期）

**现有 Agents（直接复用）**：
- `TcmEdu.Agents.QuizAgent` / `QuizGeneratorAction` — 智能组卷
- `TcmEdu.Agents.BgTaskAgent` — 长任务后台执行
- `TcmEdu.Agents.WebFetchAction` — 抓教材 URL

**第一期新增 Agents**：

```elixir
# lib/tcm_edu/agents/lesson_plan_agent.ex
# 备课摘要 → 用 reasoning_model (deepseek) 或 text_model (qwen flash)
defmodule TcmEdu.Agents.LessonPlanAgent do
  use Jido.Agent,
    name: "lesson_plan",
    description: "章节标题 + 学科 → 结构化教案大纲"
  # system_prompt: 医学教学设计专家，输出 JSON（目标/重点/过程/板书/作业）
end

# lib/tcm_edu/agents/mistake_explainer.ex
# 错题 → 三部分：错因 / 知识延伸 / 3 道同类题
# 用 qwen-flash（带 reasoning）处理
```

### 8.3 医学图片生成 Agent（第一期）

> **用途**：替代 3D 建模的"看图"需求。教师输入文字描述 → 生成医学插图 / 解剖示意图 / 病理图 / 教学配图 → 存 OSS → 作为课时附图。

```elixir
# lib/tcm_edu/agents/medical_image_agent.ex
# 调用 DashScope 文生图接口：POST /api/v1/services/aigc/text2image/image-synthesis
# model = wanx2.1-t2i-turbo
# 输入：prompt + 尺寸 + 风格（医学示意图建议：clean, diagram, labeled anatomy）
# 输出：图片 URL → 上传 OSS → 返回 {url, prompt, model}

defmodule TcmEdu.Agents.MedicalImageAgent do
  use Jido.Agent, name: "medical_image", description: "医学文字 → 教学图片"

  def generate(%{"subject" => subject, "style" => style} = _params) do
    prompt = build_prompt(subject, style)   # 中文医学提示词增强
    # 调 /api/v1/services/aigc/text2image/image-synthesis
    # model: wanx2.1-t2i-turbo
  end

  defp build_prompt(subject, style) do
    "医学教学插图，#{subject}，#{style}，贴标签解剖示意图，清晰线条，白底，无文字水印"
  end
end
```

**医学图片场景**：
- 解剖示意图（心脏 / 肺 / 肝 / 骨骼）
- 病理组织图
- 医疗器械示意图
- 教学配图（封面图 / 章节头图）

### 8.4 AI 调用协议

| 功能 | 模型 | 传输 | 前端消费 |
|------|------|------|----------|
| AI 文字对话 | qwen-flash | SSE（`/api/chat`） | `@ai-sdk/react` `useChat` |
| AI 备课 / 出题 | deepseek-v4-flash / qwen-flash | SSE（`/api/ai/*`） | `useChat` |
| AI 错题解析 | qwen-flash（带 reasoning） | SSE（`/api/quiz/ai_explain`） | `useChat` |
| 医学图片生成 | wanx2.1-t2i-turbo | 异步任务 → OSS 产物 | 轮询 / Oban 回调 |

---

## 9. 多租户与权限（第一期补强）

### 9.1 第一期多租户自助开通

```elixir
# lib/mix/tasks/tcm_edu.create_tenant.ex （已有，沿用）
mix tcm_edu.create_tenant <slug> <name> [--admin-email <email>]
```

**新增 UI**：超管 `/admin/organizations/new` 表单 → 调 RPC `create_tenant` action → 自动跑迁移 + seed + 发邀请邮件（第一期用站内信替代邮件）。

### 9.2 权限矩阵（第一期目标 ≥ 50 个权限点）

现有 30+ 权限点，新增：
- `notification:read` / `notification:write`
- `quiz:read` / `quiz:write` / `quiz:grade`
- `audit_log:read`
- `search:use`
- `ai:use_lesson_plan` / `ai:use_quiz` / `ai:use_explain` / `ai:use_medical_image`

### 9.3 跨租户安全

- RPC 调用必须带 `tenant` claim（已有 `SetTenantFromToken` plug 强制）
- `System.AuditLog` 跨租户但按 `tenant` 过滤
- 超管操作不绕过 `actor`（仅通过 `actor_attribute_equals(:__struct__, TcmEdu.System.SuperAdmin)`）

---

## 10. 部署 & 监控（第一期）

### 10.1 构建流水线

```
本机开发
  ├─ mix phx.server                # 后端 :4011
  └─ pnpm --dir frontend-monorepo dev   # 前端 :3001

打包发布
  ├─ MIX_ENV=prod mix release                          # 后端 release
  ├─ cd frontend-monorepo/apps/web && pnpm build        # Next.js 静态导出 → apps/web/out
  ├─ cd frontend-monorepo/packages/android-shell
  │   └─ pnpm cap sync android                          # 把 out/ 拷进安卓 assets
  │   └─ pnpm cap open android                          # 打开 Android Studio → assembleRelease
  ├─ docker build -t tcm-edu:v0.2.0 .                  # 后端镜像
  └─ deploy.sh                                          # 推到 111.229.72.15
```

### 10.2 健康检查

```
GET /api/health
  → 200 {"status": "ok", "db": "ok", "version": "0.2.0", "tenants": 5}
  → 503 {"status": "degraded", "db": "down"}
```

### 10.3 监控（轻量）

- 用现有 `db_stats_live` + `TcmEduWeb.Telemetry`（Phoenix 内置 `:telemetry_poller`）
- 加 `/admin/system/metrics`：Erlang VM 内存、队列长度、租户数、用户数
- 第一期不接入 Prometheus / Grafana（第二期）

### 10.4 数据库迁移

```bash
# 开发环境（增 schema 资源）
mix ash.codegen --dev      # 生成 dev 迁移
mix ash.migrate           # 应用

# 新增租户 schema 自动迁移
mix tcm_edu.migrate       # 已存在，自动跑所有 tenant_<x> 的迁移

# 生产
mix ash.codegen phase1_release_2026_07_22   # 命名迁移
mix ash.migrate
```

### 10.5 存储（OSS 复用 `kg-edu`）

```elixir
# config/runtime.exs
config :tcm_edu, TcmEdu.Storage,
  adapter: TcmEdu.Storage.Aliyun,        # 参考 kg-edu 的 Waffle.Storage.AliyunOss
  bucket: "kg-edu",                     # 复用 kg-edu 的 bucket
  region: "cn-beijing",
  endpoint: "oss-cn-beijing.aliyuncs.com",
  access_key_id: System.get_env("OSS_ACCESS_KEY_ID"),
  access_key_secret: System.get_env("OSS_ACCESS_KEY_SECRET")
  # 已沿用 kg-edu 的凭证：access_key_id=<OSS_ACCESS_KEY_ID>
  # ⚠️ secret 走环境变量，勿写死，生产通过 deploy.sh / .env 注入
```

```bash
# 上传路径设计（bucket=kg-edu）
# xingningshu/avatars/{user_id}.jpg          → 头像
# xingningshu/lessons/{tenant}/{course}/{lesson}/{media}  → 课时视频/文件
# xingningshu/questions/{tenant}/{question_id}.png → 题目附图
# xingningshu/ai/{tenant}/{prompt_hash}.png   → AI 生成的医学图
# 前缀隔离：`kg-edu` 同时给 kg-edu 与杏宁树用，需用目录前缀区分
```

---

## 11. 测试策略（第一期）

### 11.1 测试金字塔

| 层 | 工具 | 覆盖目标 |
|----|------|----------|
| **单元测试** | ExUnit + Ash 测试工具 | 所有 Ash action 100% 覆盖（happy + invalid + forbidden） |
| **集成测试** | ExUnit + `Phoenix.ConnTest` | 所有自定义 controller（auth / chat / 上传 / 心跳 / AI） |
| **E2E 测试** | Playwright（已有 `webapp-testing` skill） | 关键路径 12 条（见 §11.3） |
| **冒烟测试** | `smoke_test.exs`（已有） | 部署后自动跑一遍 |

### 11.2 多租户测试约定

```elixir
# test/support/tenant_case.ex
defmodule TcmEdu.TenantCase do
  use ExUnit.CaseTemplate
  using do
    quote do
      use TcmEdu.DataCase
      import TcmEdu.Factory

      setup do
        tenant = "tenant_test_#{System.unique_integer([:positive])}"
        Ash.create!(TcmEdu.System.Organization, %{slug: tenant, name: "Test #{tenant}"})
        {:ok, tenant: tenant}
      end
    end
  end
end
```

### 11.3 第一期 E2E 路径清单

```
P01.  学员注册 → 登录 → 浏览课程 → 选课 → 学习 → 进度上报
P02.  教师登录 → 创建课程 → 上传课时 → AI 备课 → 智能组卷
P03.  学员答题 → 错题入库 → AI 解析
P04.  学员 AI 对话 → 流式输出 → 多轮上下文
P05.  超管登录 → 创建租户 → 邀请管理员 → 管理员登录 → 配置品牌
P06.  学员断点续播（关闭 → 重开 → 自动恢复）
P07.  教师学情概览 → 雷达图渲染
P08.  管理员数据驾驶舱 6 指标渲染
P09.  移动 Web 响应式（iPhone 14 viewport 测试）
P10.  安卓 APK 安装 → 启动 → 登录 → 完成 P01 关键路径
P11.  站内信：教师发布课程 → 学员收到通知 → 红点 → 已读
P12.  操作日志：超管修改租户配置 → 日志落库 → 查询可见
```

---

## 12. 性能与可扩展性（第一期目标）

| 指标 | 目标 | 验证手段 |
|------|------|----------|
| 首页 LCP（4G 模拟） | < 2.5s | Lighthouse CI |
| 课程详情 LCP | < 2.0s | Lighthouse CI |
| 视频首帧 | < 3s | 手动 |
| API `/api/rpc/run` P99 | < 200ms | `:telemetry` |
| AI 文本流首字 | < 1.5s | 手动 |
| 安卓 APK 体积 | < 30MB | `apkanalyzer` |
| 并发租户数 | ≥ 20 | 手动（脚本模拟） |
| 单租户并发用户 | ≥ 100 | `wrk` 压测 |

---

## 13. 风险与决策清单（第一期启动前必须定）

| # | 决策项 | 默认建议 | 需谁确认 | 影响 |
|---|--------|----------|----------|------|
| D1 | 安卓打包方案 | Capacitor 6 | 客户 / 项目 owner | 安卓工期 ±2 周 |
| D2 | 应用包名 | `com.xingningshu.app` | 客户 | 上架 Play 必需 |
| D3 | 签名 keystore | 客户自有 | 客户 | 上架必需 |
| D4 | 第一期是否做微信登录 | 否（用手机号 + 密码） | 客户 | 第二期再加 |
| D5 | 第一期是否做支付 | 否 | 客户 | 已是第二期 |
| D6 | AI API 配额 | 按需付费，预算 ¥500/月 | 项目 owner | 不可控成本 |
| D7 | 演示数据范围 | 5 个租户，每租户 50 门课 / 200 用户 | 客户 | 影响演示效果 |
| D8 | 是否要 iOS TestFlight | 第二期 | 客户 | 工期 |
| D9 | 域名 | `xingningshu.example.com` 或 IP | 客户 | 上线必备 |
| D10 | 是否需要 HTTPS | 是（用 Caddy 反代自动证书） | 项目 owner | 部署复杂度 +1 步 |

---

## 14. 第一期工期建议（不开发，先对齐）

> 仅作为讨论起点，**不进入开发**。

| 周次 | 主要交付 | 备注 |
|------|----------|------|
| W01 | 启动会 + 决策 D1–D10 + 技术栈澄清备忘 | 1 周 |
| W02 | 新增 4 个 Ash 资源 + 迁移 + 种子数据 | 资源层 |
| W03 | RPC codegen + 自定义 controller（health / heartbeat / ai） | 接口层 |
| W04 | 学员端核心：课程列表 + 详情 + 试看 + 选课 | B1-B3 |
| W05 | 学员端核心：学习页 + 进度心跳 + 断点续播 | B4-B6 |
| W06 | 教师端核心：课程管理 + 课时编辑器 + AI 备课 | C1-C4 |
| W07 | 教师端核心：题库 + AI 出题 + 学情 | C5-C7 |
| W08 | 管理端核心：驾驶舱 + 权限矩阵 + 操作日志 | D1-D6 |
| W09 | AI 全链路：错题解析 + 学员对话增强 | F1-F4 |
| W10 | PWA + 移动 Web 响应式打磨 + 安装引导 | A1 |
| W11 | Capacitor 安卓壳 + 签名 + APK 出包 | A2 |
| W12 | 性能优化 + E2E 12 路径 + 冒烟 + 交付报告 | 收尾 |

**第一期总工期**：12 周（与合同 18 周对比，留 6 周给第二期 + 验收缓冲）。

---

## 15. 第一期不做的事（明确红线）

```
⛔ 不引入 React Native（除非决策改为 Taro / RN）
⛔ 不引入 WebXR / Three.js（3D / VR 棕到第二期）
⛔ 不引入 Neo4j / 图数据库（知识图谱第二期）
⛔ 不接入推送（FCM / APNs）
⛔ 不接入支付（微信 / 支付宝）
⛔ 不对接医院 HIS / LIS / EMR / PACS
⛔ 不引入 CDN / 异地灾备
⛔ 不做 SP 临床模拟 / MDT
⛔ 不做视频生成（wanx2.1-t2v / i2v，第二期）
⛔ 不做 AR / 数字人
⛔ 不做 iOS APP（第二期）
⛔ 不做微信小程序（第二期）
⛔ 不做实时语音（Omni Realtime）（第二期）
⛔ 不引入 Kafka / Redis / 分布式队列（第二期）

> ✓ 已把「医学图片生成（wanx2.1-t2i-turbo）」从第二期并入第一期
> ✓ 已把「阿里云 OSS」改为第一期启用（复用 kg-edu bucket），删除"本地根 FS"方案
```

---

## 16. 文档配套（规划阶段产出）

> 这些是规划阶段就要写完的，不是开发后才写。

| 文档 | 路径 | 用途 |
|------|------|------|
| **本方案** | `docs/xingningshu-phase1-tech-plan.md` | 第一期总方案 |
| API 文档 | `docs/api-v1.md` | 自动从 `@doc` 生成（`mix docs`） |
| 数据库 ER | `docs/er-v1.md` | 从迁移文件 + 资源自动生成 |
| 部署手册 | `docs/deploy.md` | 已有，需更新 |
| 测试报告 | `docs/test-report-phase1.md` | 第一期完工后写 |
| 交付清单 | `docs/deliverables-phase1.md` | 第一期完工后写 |
| Capacitor 手册 | `docs/capacitor-android.md` | 新建（安卓壳打包说明） |
| AI 提示词库 | `docs/ai-prompts.md` | 第一期完工后归档所有 system prompt |

---

## 17. 总结

**第一期 = 12 周的"做实"工作**：移动 Web + 安卓壳 + 现有 Ash 资源的高质量封装 + **AI 文本（qwen-flash）+ 医学图片生成（wanx2.1-t2i-turbo）** + 文件存储接入**阿里云 OSS（复用 kg-edu）**。不引入新的重型中间件，不做合同里的"硬骨头"。

**第二期预告（不在本方案展开）**：iOS APP + 医学短视频生成 + 3D/VR + AR + 实时语音（Omni Realtime）+ 数字人 + 知识图谱 + SP 模拟 + 支付 + 小程序等。这些功能要么需要新中间件，要么需要新设计，要么第二期合同可能追加预算。

**本版（V1.1）变更**：
1. 文本模型 `qwen-max` → **`qwen-flash`**（用户指定）+ deepseek-v4-flash 推理
2. 新增强制资源 **§8.0**：Qwen Key / DeepSeek Key / OSS 凭证（均沿用 `kg-edu`）
3. 新增 **AI 医学图片生成**（wanx2.1-t2i-turbo）进第一期；视频 / 3D / VR / AR / 实时语音 / 数字人缓到第二期
4. 存储本土 FS → **阿里云 OSS（kg-edu bucket）**第一期满用
5. Key 管理沿用 kg-edu 的数据库 `api_key_configs` 方案（super admin 运行时改key）

---

## 18. 已实现进度（2026-07-22 快照）

**后端资源**（全部已迁移 + 测试）：

| 模块 | 状态 | 对应计划 |
|------|------|----------|
| `TcmEdu.Quiz`（QuestionBank/Question/Attempt/Grading） | ✅ 12 测试 | §5.3 题库 |
| `TcmEdu.Notification`（Notification + Oban worker） | ✅ 5 测试 | §5.3 通知 |
| `TcmEdu.System.AuditLog` / `ApiKeyConfig` | ✅ 4 测试 | §5.3 审计/Key |
| 迁移：tenant_migrations(quiz+notif) + migrations(audit+key) | ✅ 已应用 | §10.4 |

**AI 层**（Req 直连 DashScope，参考 KnowledgeHub，mock 测试）：

| 模块 | 状态 | 对应计划 |
|------|------|----------|
| `TcmEdu.AI`（key 解析 override→DB→env） | ✅ 1 测试 | §8.0 |
| `TcmEdu.AI.Qwen`（chat / chat_stream / SSE 解析） | ✅ 4 测试 | §8.1 |
| `TcmEdu.AI.LessonPlan`（备课） | ✅ 2 测试 | F2 |
| `TcmEdu.AI.MistakeExplainer`（错题解析） | ✅ 2 测试 | F4 |
| `TcmEdu.AI.MedicalImage`（wanx2.1 文生图 + generate_and_store） | ✅ 8 测试 | F5 |
| `MistakeExplainerWorker`（Oban 缓存到 Attempt.ai_explanation） | ✅ 3 测试 | F4 闭环 |

**OSS 存储**（`xingningshu` bucket，无新依赖，v1 HMAC 签名）：

| 模块 | 状态 |
|------|------|
| `TcmEdu.Storage.OSS`（upload/delete/exists/head + 签名） | ✅ 6 测试 |
| `TcmEdu.Storage.OSS.Service`（AshStorage.Service 实现） | ✅ 5 测试 |
| config：storage → OSS.Service（测试仍用 Test service） | ✅ |

**控制器 / 路由**：

| 端点 | 状态 |
|------|------|
| `POST /api/ai/lesson_plan` | ✅ |
| `POST /api/ai/image` | ✅ |
| `POST /api/ai/mistake_explain`（异步） | ✅ |
| controller 测试 | ✅ 6 测试 |

**前端页面**（全部静态路由，typecheck 通过）：

| 页面 | 状态 |
|------|------|
| `/teacher/ai/lesson-plan`（备课助手） | ✅ |
| `/teacher/quiz`（题库管理） | ✅ |
| `/my-learning/mistakes`（错题本 + AI 解析） | ✅ |
| `/notifications`（通知中心） | ✅ |

**测试统计**：AI+Storage+Quiz+Notification+System+Workers+Controllers = **72 测试全绿**；
全量 164 测试仅剩 2 个预存在 ChatAgentTest（DashScope 402 Insufficient Balance，与本次无关）。

**待办（已知）**：
- ~~`mix precommit` 的 `--warnings-as-errors` 被预存在警告阻塞~~ ✅ **已修复（2026-07-22）**：
  - 删除 Phase 3 遗留的死代码 RBAC 资源（`Accounts.Role/Permission/RolePermission/UserRole/UserPermission` + `SyncUserPermissions`，表已删、无引用）
  - 删除 router 重复的 `get "/course"`（被 `/course/*path` 覆盖）
  - `mix compile --warnings-as-errors` 现 exit 0
- ~~`pnpm build`（output: export）被预存在阻塞~~ ✅ **已修复（2026-07-22）**：
  - `/teacher/courses/[id]/edit` 增加 `generateStaticParams`（segment layout）→ SSG 通过
  - `/login` 的 `useSearchParams` 包上 `<Suspense>`（Next.js export 要求）
  - `pnpm build` 现 26/26 全绿

**第二阶段 UI（2026-07-22）**：

| 页面 | 说明 |
|------|------|
| `/admin/ai-dashboard` | 管理员 AI 驾驶舱：Provider 配置状态 + 题库数 + 通知数 |
| `/admin/ai-keys` | AI Key 管理：setApiKeyConfig（沿用 kg-edu DB 存 key，运行时生效） |
| 菜单 | admin 菜单新增「AI 驾驶舱」「AI Key 管理」 |

**测试基础设施加固（2026-07-22）**：
- AI 测试弃用 OS env（System.put_env/delete_env），改用 `api_key_override`（Application env）→
  消除并发测试 DBConnection owner 竞态 / env 污染 flake；`db_key/0` 在 test env 跳过 DB 查询
- 全量 164 测试 3 连跑稳定（仅剩 2 个预存在 ChatAgentTest 需 DashScope 余额）

**部署（2026-07-22 · 111.229.72.15）**：

| 步骤 | 状态 | 说明 |
|------|------|------|
| `TcmEdu.Release.migrate` 重写 | ✅ | 补齐「public 迁移 + 默认租户 + 全部租户迁移」，与 `mix tcm_edu.migrate` 对齐；本地一审 scratch DB 验证通过 |
| 镜像构建/推送 | ✅ | `buildx linux/amd64 → registry.cn-zhangjiakou.aliyuncs.com/myelixir/tcm-edu:latest` |
| 服务器基础设施 | ✅ | postgres:16-alpine 容器（网络 `knowledgehub_abp-network`）+ `tcm_edu` 库 + nginx :80→:4000 |
| 迁移执行 | ✅ | public 表 + `tenant_default`（含 question_banks/questions/question_attempts/notifications）全部建成 |
| 内部验证 | ✅ | 首页/教师题库/AI驾驶舱/通知中心/静态资源 全部 HTTP 200，容器 healthy |

> ⚠️ **待办（需用户在腾讯云控制台操作）**：CVM `VM-0-10-ubuntu` 的**安全组目前只放行 22 端口**，
> 80/443/4000 公网不可达。请在安全组放行 **TCP 80**（如需 HTTPS 再加 443）后，
> `http://111.229.72.15/` 即可访问。
> （公网 000 系安全组阻塞，非服务问题——服务器内部 nginx→Phoenix 全链路已验证 200。）

> 其他部署注意：镜像仓库私有，服务器 docker 已复用本机登录凭据；`.env` 含随机 SECRET_KEY_BASE/TOKEN_SIGNING_SECRET。

**AI 联调（2026-07-22 · DashScope 充值后线上全通）**：

| 项 | 结果 |
|----|------|
| 文本 `/api/ai/lesson_plan` | ✅ qwen-flash 14.9s 生成完整教案 |
| 图片 `/api/ai/image` | ✅ wanx2.1-t2i → 落库 OSS + **预签名 URL（私有 bucket 可浏览器直读 ）** |
| 错题 `/api/ai/mistake_explain` | ✅ 答错→判分→worker AI→写回 `Attempt.ai_explanation` |
| 默认聊天 `model: :fast` | ✅ 改 `deepseek:deepseek-chat` → `alibaba_cn:qwen-flash`（DeepSeek 账户无余额，Qwen 已充值） |
| 165 测试 | ✅ 全绿（含原先 2 个 ChatAgent 预存在失败） |

**线上修复（联调中发现）**：
1. `TcmEdu.AI` 原在函数内调 `Mix.env()` → release 崩溃 → 改**编译期 `@env` 常量**
2. OSS 私有 bucket 匿名 403 → 新增 `OSS.signed_url/2`（v1 预签名，默认 1h 过期），`generate_and_store` 返回签名 URL
3. `api_key_override` 语义：`:none` = 强制无 key（测试稳定，不受系统 env 影响）

**前端新增（2026-07-22）**：`/teacher/ai/image`（AI 医学图片生成：模板+风格+尺寸，结果 `<img>` 直接展示签名图）。

---

**文档结束 · 杏宁树项目组 · 2026-07-22**