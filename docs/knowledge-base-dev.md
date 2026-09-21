# 知识库（租户知识适配 RAG）开发文档

> 状态：持续迭代
> 仓库：`/Users/bai/projects/tcm-edu`

## 1. 已实现

| 能力 | 说明 | 模块 |
|---|---|---|
| 向量检索 RAG | AshAi `vectorize`（pgvector，text-embedding-v3 1024 维）+ `vector_cosine_distance` 语义检索 | `TcmEdu.Knowledge.TenantDoc` / `search_top_docs` |
| 文档解析 | `extractous_ex`（Apache Tika）解析 docx/xlsx/pptx/pdf/odt… | `DocumentExtractor` |
| 结构感知分片 | 按 h1-h6 标题切成语义章节块（`## 标题` 前缀） | `Ingestion.chunk_blocks` |
| 异步嵌入 | Oban worker 计算向量 + PubSub 广播状态，教师页自动刷新 | `TenantDocEmbeddingWorker` |
| 问答引用溯源 | AI 回答附带「依据《章节》」标签，历史消息回显 | `QaChat.ask_with_references` / `AiChatLive` |
| 索引/问答开关 | 每个源可开/关「参与索引」「参与问答」，问答检索只命中开启资源 | `indexed` / `in_chat` / `search_top_docs(in_chat_only: true)` |
| 媒体资源 | 图片/视频上传存 OSS + 图片缩略图（OSS 图片处理 resize）+ 预览 | `Ingestion.ingest_media` |
| 文档预览 | 简化版：提取文本前 600 字 | `Ingestion.preview` / 教师页预览 modal |
| 源级 CRUD | 教师页：上传、编辑（标题/类型）、删除、刷新 | `TeacherAIKnowledgeLive` |
| HNSW 索引 | 租户表 `tenant_docs` 向量列 HNSW（>10k 文档时检索不退化） | `20260921200001_add_tenant_doc_hnsw_index.exs` |

## 2. 剩余候选（短期，未排期）

- **管理端跨租户知识库审计视图**：超管查看各租户知识库规模（文档数/已嵌入/失败/开关状态）。
- **分片/检索参数配置化 UI**：`chunk_chars`（默认 1200）、检索 `top_k`、距离阈值（当前 0.6）已支持
  `Application.put_env` 覆盖，可做成租户级配置页。
- **全文检索混合召回**：tsvector 关键词召回 + 向量语义召回融合，提升专有名词（药名/穴名）命中率。
- **embedding 模型可选**：`text-embedding-v3` / `v4` 切换 + 维度配置。
- **上传防重**：按文件哈希去重，避免重复入库。

## 3. 后续开发项（图片/视频处理深化）

- **视频缩略图**：视频上传后抽帧生成 poster（需 ffmpeg，或 OSS 视频截帧服务）。
- **图片/视频 OCR / 理解**：图片进向量（多模态 embedding）、视频关键帧识别——为「医学影像讲解」铺路。
- **文档富预览**：docx 转 HTML / PDF 内嵌预览（当前为纯文本片段）。
- **分片单元测试增强**：长文档跨章节边界、图片穿插文档的处理。
- **管理端统一配置**：把 §2 的参数配置做成管理 UI。