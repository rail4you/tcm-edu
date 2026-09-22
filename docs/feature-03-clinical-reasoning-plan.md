# Feature #3 — AI 临床思维与决策推理引擎（方案规划）

> 状态：规划中 → 已确认按此文档从 M0 开始开发
> 关联文件：`lib/tcm_edu/simulated_patient/*`、`lib/tcm_edu/ai/simulated_patient*.ex`、`student/teacher_simulated_patient_live*`

## 一、需求（原始）

1. 支持全流程临床模拟：问诊→体格检查→辅助检查→诊断→鉴别诊断→治疗方案→随访
2. 实时对比标准诊疗路径，标注学员思维漏洞，给出详细改进建议
3. 难度分级：入门（典型病例）→进阶（复杂病例）→专家（疑难杂症）→急诊（危重病例）
4. 支持多学科联合诊疗（MDT）模拟：多个学员分别扮演不同科室医生，AI 扮演患者与其他科室专家
5. 生成临床思维能力报告：分析学员在诊断准确性、鉴别诊断全面性、治疗合理性等方面的短板

## 二、现状盘点

已有「模拟诊疗（标准化病人 SP）」模块，与目标强相关且重度重叠，采用**增量扩展**而非另起炉灶。

### 已有能力（可复用）
- `Patient`：主诉/病史/人设/关键点/rubric/**难度1-5**（租户域）
- `Assignment` / `Session` / `Message` / `Evaluation`：完整会话与评分记录
- `AI.SimulatedPatient`：AI 扮演病人，问诊对话
- `AI.SimulatedPatientEvaluator`：对话后评分（专业/同理心/沟通）
- 教师端配置 + 学生端对话 + 异步评分（`Workers`）
- AI 调用层：Qwen（qwen-flash/qwen-plus），Req 实现，强力 JSON 容错，测试可插桩
- `examples.ex`：教师一键载入 mock 病例

### 缺口（本特征的增量）
1. 全流程只到「问诊」，缺 体格检查→辅助检查→诊断→鉴别诊断→治疗方案→随访
2. 无「标准诊疗路径」定义与实时对比、思维漏洞标注
3. 难度仅数字 1-5，无 入门/进阶/专家/急诊 语义与分级设计
4. MDT 多角色模拟完全缺失
5. 临床思维能力报告（诊断准确性/鉴别全面性/治疗合理性）完全缺失

## 三、数据模型扩展（在现有 SP 域上加，不新建域）

### 1. 扩展 `Patient`
- `difficulty_level`：`:introductory` / `:advanced` / `:expert` / `:emergency`，映射现有 1-5
- `standard_pathway`（map）：按阶段的「标准动作清单」（对比基准）
- `red_flags`（`{:array, :string}`）：急诊用例需优先识别的危重信号

### 2. 新增 `CaseStage`（阶段进度，session 1:N）
- `session_id`、`stage`（7 阶段之一）、`order`、`status`(locked/available/completed/skipped)、`student_actions`(JSON)、`completed_at`

### 3. 新增 `ClinicalReasoningReport`（报告资源）
- `student_id`、周期聚合、六维打分明细、rank、statistics、`improvement_plan`、`generated_at`

### 4. 扩展 `Evaluation`
- 加 diagnostic 维度：诊断准确性 / 鉴别诊断全面性 / 治疗合理性

## 四、AI 服务层（新增模块）
- `AI.ClinicalReasoning`：阶段状态机推进
- `AI.StandardPathwayComparator`：实时对比 + red flag 警报
- `AI.StageGrader`：每阶段评分 + 改进建议
- `AI.MdtFacilitator`：multirole 角色扮演
- `AI.ReasoningReportGenerator`：跨会话聚合六维报告

## 五、前端 UI
- 学生端会话页：阶段 stepper + 实时路径对比面板（绿/红/橙标注，red flag 强警示）+ 报告页
- 教师端：标准路径配置、难度分级、按维度筛选学生报告
- 学生 MDT 入口：MDT 会诊室列表 + 会话页（多角色，AI 以专家身份发言）

## 六、难度分级设计
| 分级 | 现有 difficulty | 要点 |
|---|---|---|
| 入门 intro | 1-2 | 典型病例、线性路径、hint 多、无陷阱 |
| 进阶 advanced | 3 | 症状叠加需鉴别、路径分叉 |
| 专家 expert | 4 | 不典型/罕见、多分支、依赖辅助检查因果 |
| 急诊 emergency | 5 | 危重、red_flags、顺序严格（先救命后诊断）、漏 flag 即降级 |

## 七、MDT 设计（较重的独立子域）
- 数据：`MdtRoom`（病例/参与学生/角色/阶段）、`MdtMessage`（带 role）
- 流程：教师建 MDT 病例并分配科室角色 → 学生各自扮演本科室医生 → AI 扮演患者 + 其他科室专家（只懂本科室、坚持本科室立场）→ 汇总意见产出共同诊断与方案
- 评分：科内动作合理度 + 会诊协作度（转诊恰当/尊重他科/整合多科信息）
- 本轮先用 mock 单房间验证角色扮演机制

## 八、Mock 数据策略
`clinical_cases.ex`：5-7 个分级用例（入门/进阶/专家/急诊 + MDT 病例），每个带完整 `standard_pathway` 与 SP 病史，教师端一键载入示例。急诊用例强调 red flag。

## 九、里程碑与任务拆解（合计约 9 工作日）
- **M0 奠基**（0.5d）：扩展 Patient、新增 CaseStage / ClinicalReasoningReport、扩展 Evaluation 维度、codegen+迁移审查
- **M1 全流程引擎**（2.5d)：`AI.ClinicalReasoning` 状态机、`AI.StandardPathwayComparator`、`AI.StageGrader`、学生会话 UI 改造
- **M2 难度分级**（1d）：分级配置化 + mock 病例四级补齐 + 教师端载入
- **M3 MDT**（2.5d）：`MdtRoom`/`MdtMessage`/`AI.MdtFacilitator`、学生会诊室 UI、mock 端到端
- **M4 临床思维报告**（1.5d)：`AI.ReasoningReportGenerator`、报告页、异步生成
- **M5 测试/迁移收口/验收**（1d）：PhoenixTest 全流程、final codegen、`mix precommit` 全绿