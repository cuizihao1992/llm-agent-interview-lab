# LLM Agent Interview Lab

这个项目用于系统学习大模型 Agent 算法面试中的高频知识点，并为后续开发 RAG、AI 记忆系统、长上下文实验代码预留工程结构。

## 项目目标

- 把高频面试题拆成结构化知识文档，便于复习和扩展。
- 沉淀可复用的 RAG 数据工程、记忆机制、检索优化代码骨架。
- 后续可扩展为一个本地知识库问答系统或面试训练工具。

## 内容模块

| 模块 | 文档 |
| --- | --- |
| 长期陪伴型 AI 记忆机制 | [docs/01-memory-mechanism.md](docs/01-memory-mechanism.md) |
| RAG 向量数据工程全流程 | [docs/02-rag-vector-data-engineering.md](docs/02-rag-vector-data-engineering.md) |
| 长上下文模型与 RAG 的关系 | [docs/03-long-context-vs-rag.md](docs/03-long-context-vs-rag.md) |
| Transformer 超长上下文瓶颈与优化 | [docs/04-transformer-long-context.md](docs/04-transformer-long-context.md) |
| 面试回答模板 | [docs/interview-answer-templates.md](docs/interview-answer-templates.md) |
| 学习路线 | [docs/learning-roadmap.md](docs/learning-roadmap.md) |

## 工程结构

```text
llm-agent-interview-lab/
  configs/              # 模型、切片、检索等配置
  data/                 # 原始文档、处理中间结果、向量库数据
  docs/                 # 知识库文档
  src/                  # 后续开发代码
    agent_memory/       # AI 记忆机制
    rag_pipeline/       # RAG 数据处理与检索链路
    long_context/       # 长上下文实验
  tests/                # 单元测试
```

## 后续开发方向

1. 实现文档解析、清洗、切片、向量化、入库。
2. 实现向量检索、关键词检索、混合检索和重排序。
3. 实现短期记忆、实体画像记忆、长期情景记忆。
4. 增加面试问答训练数据，构建本地 RAG 问答 Demo。
5. 做长上下文实验，对比“全量上下文”和“RAG 召回后精读”的成本、延迟、准确率。

## 快速开始

当前版本以文档和代码骨架为主，暂未绑定具体模型或向量数据库。

后续如果使用 Python 开发，可先创建环境：

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -e .
```

运行占位测试：

```powershell
pytest
```
