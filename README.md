# LLM Agent Interview Lab

面向大模型 / Agent 算法面试的知识库与可运行 MVP。

这个项目现在包含两部分：

- `site/`：可部署到 GitHub Pages 的知识学习页面。
- `src/interview_lab/`：可本地运行的 RAG + 向量库 + Agent 记忆 + 模型适配 MVP。

## 在线页面

GitHub Pages:

```text
https://cuizihao1992.github.io/llm-agent-interview-lab/
```

## 核心能力

### 1. 知识库

文档位于 `docs/`，覆盖：

- 长期陪伴型 AI 记忆机制
- RAG 向量数据工程
- 长上下文模型与 RAG 的关系
- Transformer 超长上下文瓶颈与优化
- 面试回答模板
- 学习路线

### 2. RAG

已实现最小可运行链路：

```text
Markdown 文档 -> 语义切片 -> 本地 embedding -> SQLite 向量库 -> 相似度检索 -> Prompt 上下文
```

当前 MVP 使用本地 `HashingEmbeddingModel`，不需要 API Key。后续可以替换为 OpenAI embedding、bge、Qwen embedding 等真实模型。

### 3. Agent 记忆

已实现三层记忆：

- 短期记忆：最近对话轮次。
- 实体画像记忆：用户目标、偏好、身份等结构化事实。
- 长期情景记忆：用户消息向量化后存入 SQLite，提问时语义召回。

### 4. 模型接入

默认使用 `MockLLM`，可以不联网跑通完整链路。

需要真实模型时，可使用 OpenAI-compatible Chat API：

```powershell
$env:OPENAI_API_KEY="你的 API Key"
$env:OPENAI_MODEL="gpt-4.1-mini"
$env:OPENAI_BASE_URL="https://api.openai.com/v1"
interview-lab ask "RAG 的工程链路是什么？" --real-llm
```

兼容其他 OpenAI API 风格平台，只需要改 `OPENAI_BASE_URL` 和 `OPENAI_MODEL`。

## 快速开始

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -e .
```

初始化数据库：

```powershell
interview-lab init-db
```

把 `docs/` 索引进本地向量库：

```powershell
interview-lab index-docs --docs docs --clear
```

使用 Mock 模型提问：

```powershell
interview-lab ask "长期陪伴型 AI 的记忆机制怎么设计？"
```

添加一条结构化用户画像事实：

```powershell
interview-lab add-fact --key goal --value "准备大模型 Agent 算法面试"
```

进入连续对话：

```powershell
interview-lab chat
```

## 工程结构

```text
llm-agent-interview-lab/
  .github/workflows/       # GitHub Pages 自动部署
  configs/                 # RAG 与记忆配置草案
  data/                    # 本地数据目录，运行时 SQLite 不提交
  docs/                    # 面试知识库文档
  site/                    # GitHub Pages 静态学习页面
  src/
    interview_lab/         # 可运行 MVP 核心
      agent.py             # Agent 编排
      cli.py               # 命令行入口
      embeddings.py        # 本地 embedding MVP
      llm.py               # Mock / OpenAI-compatible 模型接口
      memory.py            # 三层记忆体系
      rag.py               # Markdown 索引与检索
      vector_store.py      # SQLite 向量库
    agent_memory/          # 早期记忆模块草案
    rag_pipeline/          # 早期 RAG 模块草案
    long_context/          # 长上下文分析工具
  tests/                   # 单元测试
```

## 后续演进

1. 把 `HashingEmbeddingModel` 替换为真实 embedding provider。
2. 把 `SQLiteVectorStore` 替换为 Qdrant、Milvus、Chroma 或 pgvector。
3. 用 LLM 做记忆抽取，替换当前启发式事实抽取规则。
4. 增加 FastAPI 服务层，让 `site/` 可以直接调用本地后端。
5. 增加面试回答评分、知识盲区诊断和复习计划。

## 验证

```powershell
python -m pytest
```

更多架构说明见 [docs/mvp-architecture.md](docs/mvp-architecture.md)。
