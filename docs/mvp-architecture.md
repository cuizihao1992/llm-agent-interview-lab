# MVP 架构说明

这个项目现在包含一个可运行的本地 MVP，用于把知识库、RAG、向量库、Agent 记忆和模型调用串成完整链路。

## 目标

MVP 的目标不是一开始就追求生产级召回效果，而是先保证架构真实：

```text
Markdown 知识文档
  -> 语义切片
  -> Embedding
  -> SQLite 向量库
  -> RAG 检索
  -> Agent 记忆召回
  -> Prompt 组装
  -> LLM 回答
  -> 对话与记忆写回
```

## 已包含模块

| 模块 | 文件 | 作用 |
| --- | --- | --- |
| Embedding | `src/interview_lab/embeddings.py` | 本地哈希向量 MVP，可替换真实 embedding 模型 |
| 向量库 | `src/interview_lab/vector_store.py` | SQLite 持久化 chunk 和向量，支持余弦检索 |
| RAG | `src/interview_lab/rag.py` | Markdown 索引、语义切片、知识召回 |
| 记忆体系 | `src/interview_lab/memory.py` | 短期对话、画像事实、长期情景记忆 |
| 模型接口 | `src/interview_lab/llm.py` | MockLLM 与 OpenAI-compatible Chat API |
| Agent 编排 | `src/interview_lab/agent.py` | 组合 RAG、记忆和模型，输出回答 |
| CLI | `src/interview_lab/cli.py` | 初始化、索引、提问、聊天、手动加事实 |

## 记忆体系

MVP 记忆分三层：

1. 短期记忆：最近多轮对话，保存在 `dialogue_turns`。
2. 实体画像记忆：结构化事实，保存在 `profile_facts`。
3. 长期情景记忆：用户消息向量化后保存到 `episodic_memories`，提问时按语义召回。

当前事实抽取是启发式规则，例如：

- `我是...`
- `我喜欢...`
- `我的目标是...`
- `我正在...`
- `我想学习...`

后续可以替换成 LLM 信息抽取器。

## RAG 与向量库

当前向量库使用 SQLite 存储：

- chunk id
- document id
- chunk text
- metadata
- embedding

检索阶段使用本地哈希 embedding 和余弦相似度线性扫描。这个方案适合 MVP 和小规模知识库，后续可以替换为：

- Qdrant
- Milvus
- Chroma
- pgvector

## 模型接入

默认使用 `MockLLM`，不需要 API Key。

接入真实模型时使用 OpenAI-compatible API：

```powershell
$env:OPENAI_API_KEY="你的 API Key"
$env:OPENAI_MODEL="gpt-4.1-mini"
$env:OPENAI_BASE_URL="https://api.openai.com/v1"
interview-lab ask "RAG 为什么不能只靠向量检索？" --real-llm
```

如果使用兼容 OpenAI API 的其他平台，只需要改 `OPENAI_BASE_URL` 和 `OPENAI_MODEL`。

