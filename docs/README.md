# TCM-Edu · 设计与开发文档

本目录是 **tcm-edu（中医教学系统）** 的完整设计与开发文档。

## 📂 文档结构

| 文档 | 用途 | 阅读对象 |
|------|------|----------|
| [`tcm-edu-dev-plan.md`](./tcm-edu-dev-plan.md) | **主开发方案**：架构设计、域模型、Ash 资源、API、前端、分阶段计划 | 所有人 |
| [`tcm-edu-progress.md`](./tcm-edu-progress.md) | **进度跟踪**：每个 Phase / Task 的 checklist，实施时实时打钩 | 开发执行者 |

## 🎯 系统定位

- **领域**：中医在线教育（参考人民医学网类站点的业务形态）
- **核心特色**：多租户（每个机构/学校一个独立租户）、多角色（超管/租户管理员/教师/学生）
- **技术栈**：Phoenix 1.8 + Ash 3 + AshTypescript + PostgreSQL（schema 多租户）
- **前端**：管理端/教师端用 Antd；学生端用 Next.js + 自定义 React 组件（更灵活、更轻）

## 🚦 当前阶段

Phase 0：方案设计文档（**当前**）→ 等待用户 review 后开始 Phase 1。

## 📖 阅读顺序建议

1. **总览** → `tcm-edu-dev-plan.md` 第 1、2、3 节
2. **数据模型** → 第 4、6 节
3. **前后端对接** → 第 7、8 节
4. **分阶段计划** → 第 10 节
5. **日常开发** → 边看 `tcm-edu-progress.md` 边打钩

## ⚠️ 注意事项

- **方案确定后再写代码**：当前所有架构决策都需要 review；如有不同意见，先改文档再实现
- **每完成一个 Phase** 就 commit + 更新 `tcm-edu-progress.md` 的勾选状态
- **域命名约定**：本文档统一用 `tenant_<slug>` 作为 schema 名（不是 kg-edu 的 `org_<uuid>`，便于阅读）