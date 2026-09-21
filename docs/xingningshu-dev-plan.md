# 杏宁树 · 开发计划（Master Plan）

> **版本**：V1.0
> **编制日期**：2026-07-22
> **产品名**：**杏宁树**（XingNingShu）
> **产品全称**：杏宁树 · 智能医学教育综合在线平台
> **Slogan**：杏林传薪 · AI 树人
> **仓库**：`/Users/bai/projects/tcm-edu`
> **阶段**：分两期（第一期 = 移动 Web + 安卓 + 文本 AI + 医学图片；第二期 = 硬骨头能力）
> **状态**：规划中，未开始开发

---

## 目录

1. [命名与标识规范（统一应用名称）](#1-命名与标识规范统一应用名称)
2. [项目定位与背景](#2-项目定位与背景)
3. [合同关键约束](#3-合同关键约束)
4. [分期规划总览](#4-分期规划总览)
5. [第一期范围与工期](#5-第一期范围与工期)
6. [第二期预告](#6-第二期预告)
7. [第一期技术架构](#7-第一期技术架构)
8. [关键决策清单](#8-关键决策清单)
9. [文档与配套](#9-文档与配套)

---

## 1. 命名与标识规范（统一应用名称）

> 这是本项目第一优先级：**在动手写任何端之前，把应用名称统一为「杏宁树」**，否则改造成本随时间累积。

### 1.1 统一命名表（唯一口径）

| 维度 | 统一值 | 说明 |
|------|--------|------|
| 中文产品名 | **杏宁树** | 所有用户可见处使用 |
| 英文产品名 | **XingNingShu** | 国际/代码可读用 |
| 产品代号（短） | **XNS** | 内部简写、测试标签 |
| 产品全称 | 杏宁树 · 智能医学教育综合在线平台 | 用于注册登记 / 合同 / 官网 footer |
| Slogan | 杏林传薪 · AI 树人 | 首页 hero / 登录页 |
| 中文 Slogan 备选 | 传承岐黄 · 智启杏林 | 供市场选择 |
| 域名（建议） | `xingningshu.cn` / `xns.cn` | 需客户确认并备案 |
| 浏览器标题 | 杏宁树 \| 课程 / 学习 / 导师 等 | 每页 `metadata.title` |
| 手机桌面名（PWA） | 杏宁树 | `manifest.json` |
| Android 应用名 | 杏宁树 | `Capacitor appName` |
| iOS 应用名 | 杏宁树 | 第二期 |
| 应用包名（Android/iOS） | `com.xingningshu.app` | 上架必需 |
| 主题色 | 杏暖 `#C97B4A` + 宁墨绿 `#2F5D50` | 待客户确认 |
| 主字体 | Noto Serif SC（标题）+ Noto Sans SC（正文） | 已在 layouts 加载 |

### 1.2 现有名称分布（需统一的位置清单）

当前仓库存在**混用**情况，必须在第一期 W1（命名统一工作项）逐一修正：

| # | 位置 | 当前值 | 统一为 | 类型 |
|---|------|--------|--------|------|
| 1 | `apps/web/app/layout.tsx` → `metadata.title` | `中医教学 · 传承岐黄之术` | `杏宁树` | 页面标题 |
| 2 | `apps/web/app/(student)/course/page.tsx` → `title` | `课程详情 · 中医教学` | `课程详情 · 杏宁树` | 页面标题 |
| 3 | 其它各页 `metadata.title` | `中医教学` 后缀 | `杏宁树` 后缀 | 页面标题 |
| 4 | `apps/web/app/(student)/robots.ts` | `tcm-edu.example.com` | `xingningshu.example.com` | SEO |
| 5 | `apps/web/app/(student)/sitemap.ts` → `BASE_URL` | `tcm-edu.example.com` | `xingningshu.example.com` | SEO |
| 6 | 首页 hero 文案 | 「中医教学系统」等 | 「杏宁树 · 智能医学教育平台」 | 文案/品牌 |
| 7 | `frontend-monorepo/*/package.json` → `name` | `@tcm-edu/*` | `@xingningshu/*` | npm 作用域 |
| 8 | `mix.exs` → `app:` | `:tcm_edu` | `:xingning_shu` | OTP app |
| 9 | Elixir 模块前缀 | `TcmEdu.*` | `XingNingShu.*` | 代码模块 |
| 10 | `config/*.exs` 里的 app key | `:tcm_edu` | `:xingning_shu` | 配置 |
| 11 | `docker` 镜像名 / `rel` | `tcm_edu` | `xingning_shu` | 部署 |
| 12 | OSS 目录前缀（计划中） | （尚无） | `xingningshu/` | 存储前缀 |
| 13 | 部署域名 / `deploy.sh` 内 REMOTE | `tcm-edu` | `xingningshu` | 运维 |
| 14 | 文档标题 | `TCM-Edu` 混用 | `杏宁树` | 文档 |

> **重要**：Elixir OTP app 名（#8–#11）与模块前缀（#9）的重命名是**大改动**，会影响所有 `use Ash.Resource`/迁移/路由/Web 模块。放在**第一期 W1** 作为专项做，用 Igniter 迁移工具 + `--dry-run` 预演，避免手工遗漏。若客户接受，可在第二期再统一代码内部代号（先只改用户可见的 1–7、12–14，降低风险）。

### 1.3 命名统一工作项（W1，独立交付）

```
W1.0  建《杏宁树品牌规范》文档（本章内容落地为独立文档）
W1.1  客户签字确认应用名、包名、Slogan、域名（D1–D10 决策单）
W1.2  统一前端用户可见名称：layout / 各页 title / hero 文案（#1–#3、#6）
W1.3  统一前端 SEO：robots.ts / sitemap.ts 域名（#4–#5）
W1.4  统一 npm scope：@tcm-edu/* → @xingningshu/*（#7）
W1.5  评估 Elixir app/模块重命名成本，产出一份《重命名影响分析》（#8–#11）+
      用 Igniter 生成 dry-run 迁移脚本，是否执行由客户决定
W1.6  建立 OSS 前缀约定 `xingningshu/`（#12）
W1.7  更新 deploy.sh / 运维文档的域名与容器名（#13–#14）
验收：全仓库无 `tcm-edu`（除 git 历史遗留）+ 无 `中医教学` 字样的用户可见文案
```

---

## 2. 项目定位与背景

面向医学从业者、医学院校、三甲医院、基层医疗机构、培训机构与行业协会的**智能终身教育平台**。

- 覆盖 PC / 移动 Web / 安卓 / iOS（编）四端
- 聚焦中医 + 现代医学交叉教学，AI 化学习体验
- 多租户独立部署、数据隔离

**技术基因**：Phoenix 1.8 + Ash 3 + AshPostgres + AshAuthentication + Next.js 16 + Jido AI + Oban + PostgreSQL（schema 多租户）。

---

## 3. 合同关键约束

| 项 | 约束 | 影响 |
|----|------|------|
| 周期 | 18 周（合同） | 本计划分两期，第一期占前段 |
| 金额 | ¥90,000（4 期） | 里程碑对齐验收 |
| 多端 | PC / iOS / 安卓 / 微信小程序 | 第一期移动 Web + 安卓，其余二期 |
| AI | 国产大模型，DeepSeek + 通义千问 | 第一期 qwen-flash + 图片生成 |
| 范围 | 七层架构 / AI / 3D / 多租户 / 支付 | 3D/VR/支付等第二期 |
| 硬件对接 | 附件清单 | 不在主线，推动甲方准备 |

---

## 4. 分期规划总览

| 期 | 代码生产 | 时长 | 目标 |
|----|----------|------|------|
| **第一期** | 是 | 12 周（W1–W12） | 移动 Web（PWA）+ 安卓（Capacitor）+ 现有架构功能 + 文本 AI（qwen flash）+ 医学图片生成 + OSS 存储 |
| **第二期** | 是（范围预告） | ≥ 6 周 | iOS APP + 医学短视频生成 + 3D/VR + AR + 实时语音 + 数字人 + 知识图谱 + SP 模拟 + 支付 + 小程序 |

> 第二期**不随本计划开发**，仅锁定范围边界，避免第一期被"硬骨头"拖慢。合同 18 周中，第一期 12 周 + 第二期 6 周。

---

## 5. 第一期范围与工期

### 5.1 做什么

```
端：
  A1. 移动 Web（响应式 Next.js + PWA 安装提示）
  A2. 安卓 APP（Capacitor 6 壳包 Next.js）
  A3. 现有 PC 三端（学员/教师/管理）继续完善

学员：
  B1. 注册/登录           B2. 课程浏览/详情/试看
  B3. 选课 + 我的学习       B4. 课时学习（视频/文章/PDF）
  B5. 进度心跳上报         B6. 断点续播
  B7. AI 文字导师（qwen flash）
  B8. 错题 AI 解析         B9. 个人中心

教师：
  C1. 工作台               C2. 课程/章节/课时 CRUD
  C3. 课时编辑器           C4. AI 备课助手（deepseek/qwen）
  C5. 题库管理             C6. AI 智能组卷基础
  C7. 学情概览（雷达图）

管理端：
  D1. 多租户自助开通        D2. 用户/角色管理
  D3. 课程审核             D4. 数据驾驶舱（6 指标）
  D5. 权限矩阵             D6. 操作日志

平台能力：
  E1. 全文搜索（PG tsvector）  E2. 站内通知（Oban）
  E3. 文件上传（OSS）        E4. AI 医学图片生成（wanx2.1-t2i-turbo）

AI（文本 + 图片）：
  F1. 文字导师   F2. 备课助手   F3. 智能组卷   F4. 错题解析   F5. 医学图片生成
```

### 5.2 不做（第二期）

```
视频生成（wanx2.1-t2v/i2v）、3D/VR、AR、实时语音（Omni Realtime）、
数字人、知识图谱（Neo4j）、SP 临床模拟、MDT、支付（微信/支付宝）、
微信小程序、iOS、推送（FCM/APNs）、医院 HIS/LIS/EMR/PACS 对接、CDN/灾备
```

### 5.3 工程代码边界

| 域 | 新增代码 |
|----|----------|
| 新 Ash 资源 | `Notification` / `AuditLog` / `Question` / `QuestionBank` / `Attempt` / `ApiKeyConfig` |
| 新 Agent | `LessonPlanAgent` / `MistakeExplainer` / `MedicalImageAgent` |
| 新 controller | `health` / `heartbeat` / `notifications` / `ai/*` / `quiz/*` / `search` / `tenant` |
| 移动端 | `packages/android-shell`（Capacitor）+ `apps/web/out` 静态导出 |
| 存储 | AshStorage → 阿里云 OSS（复用 kg-edu bucket） |

### 5.4 工期表（12 周）

| 周 | 交付 |
|----|------|
| W1 | 命名统一（§1.3）+ 品牌规范 + 决策单 |
| W2 | 新增 6 个 Ash 资源 + A migration + seed |
| W3 | RPC codegen + 自定义 controller（health/heartbeat/ai） |
| W4 | 学员：课程列表/详情/试看/选课 |
| W5 | 学员：学习页 + 进度心跳 + 断点续播 |
| W6 | 教师：课程管理 + 课时编辑器 + AI 备课 |
| W7 | 教师：题库 + AI 出题 + 学情 |
| W8 | 管理：驾驶舱 + 权限矩阵 + 操作日志 |
| W9 | AI：错题解析 + 学员对话增强 |
| W10 | PWA + 移动 Web 响应式 + 安装引导 |
| W11 | Capacitor 安卓壳 + 签名 + APK 出包 |
| W12 | 性能 + E2E 12 路径 + OSS 验收 + 交付报告 |

---

## 6. 第二期预告

```
- iOS APP（Capacitor iOS target，复用第一期安卓工程）
- 微信小程序（Taro 或 H5 嵌入，决策）
- 医学短视频生成（wanx2.1-t2v / i2v）
- 3D 解剖 + VR（Three.js + WebXR）
- AR 解剖助手
- 实时语音交互（Qwen Omni Realtime）
- AI 数字人讲师 / 代课
- 知识图谱（Neo4j / PG 图存储）
- AI SP 临床模拟 + MDT
- AI 生成 PPT / 自动出卷 / 自动剪辑
- AI 防作弊双机位（OSCE）
- 统一支付（微信 / 支付宝）
- 联邦学习 / 双活灾备
- 院校教务 / 一卡通 / 门禁 / HIS / LIS / EMR / PACS 对接
- CDN / 异地灾备 / 推送
```

---

## 7. 第一期技术架构

```
  移动 Web (PWA) ───── Android (Capacitor) ───── PC 三端
         │                │     移植 Next.js 静态导出
         └──────── Next.js 16 (apps/web) :3001 ──┘
                          │ Bearer Token
                          │ POST /api/rpc/run | /api/chat (SSE) | upload
                          ▼
                   Phoenix 1.8 (Elixir, xingning_shu)
                     Ash RPC  |  Oban  |  Jido Agents |  AshAuth
                          │
            ┌─────────────┴──────────────────┐
            ▼                                 ▼
     PostgreSQL 13+ (schema 多租户)      AI 服务 (OpenAI 兼容)
     public / tenant_default / tenant_*    qwen-flash | qwen-plus
                                           deepseek-v4-flash
                                           wanx2.1-t2i-turbo (医学图片)
            │                                 │
            └──────────────┬──────────────────┘
                           ▼
              Docker release @111.229.72.15
              阿里云 OSS（kg-edu bucket / xingningshu/前缀）
```

**关键选型**（详见 `docs/xingningshu-phase1-tech-plan.md`）：
- 安卓：**Capacitor 6**（复用 Next.js 100%）
- 文件：**阿里云 OSS**（复用 kg-edu）
- AI：qwen-flash 文本 + wanx2.1-t2i-turbo 医学图片
- key：数据库 `api_key_configs` 表 + env 注入（沿用 kg-edu 方案）

---

## 8. 关键决策清单（W1 必须定）

| # | 决策 | 默认建议 | 谁确认 |
|---|------|----------|--------|
| D1 | 应用包名 | `com.xingningshu.app` | 客户 |
| D2 | 签名 keystore | 客户自有 | 客户 |
| D3 | 一期是否做微信登录 | 否（手机号+密码） | 客户 |
| D4 | 一期是否做支付 | 否 | 客户 |
| D5 | AI 配额预算 | 文本 flash 已省，图片生成加预算 ≤¥500/月 | 项目 owner |
| D6 | OSS 归属 | 复用 kg-edu bucket，`xingningshu/` 前缀隔离 | 项目 owner |
| D7 | 演示数据 | 5 租户 × 50 课 × 200 用户 | 客户 |
| D8 | 域名 | `xingningshu.cn`（需备案）或 IP | 客户 |
| D9 | HTTPS | 是（Caddy 自动证书） | 项目 owner |
| D10 | 是否第一期做 iOS TestFlight | 第二期 | 客户 |
| D11 | Elixir 模块重命名（tcm_edu→xingning_shu） | 第一期 W1 用 Igniter dry-run 评估，是否落地待客户决定 | 客户 + 项目 owner |

---

## 9. 文档与配套

| 文档 | 路径 | 状态 |
|------|------|------|
| **本计划（Master）** | `docs/xingningshu-dev-plan.md` | ✅ 本文件 |
| 第一期技术方案（详细） | `docs/xingningshu-phase1-tech-plan.md` | ✅ V1.1 |
| 合同对齐版（18 周甘特） | `docs/xingningshu-v2-dev-plan.md` | ✅ 存在 |
| 品牌规范 | `docs/xingningshu-branding.md` | ⏳ W1 建 |
| 部署手册 | `docs/deploy.md` | ⏳ 更新 |
| Capacitor 安卓手册 | `docs/capacitor-android.md` | ⏳ W11 建 |

---

**文档结束 · 杏宁树项目组 · 2026-07-22**