from interview_lab.agent import InterviewAgent
from interview_lab.embeddings import HashingEmbeddingModel
from interview_lab.llm import MockLLM
from interview_lab.memory import MemoryStore
from interview_lab.models import Chunk
from interview_lab.rag import RagEngine
from interview_lab.vector_store import SQLiteVectorStore


def test_vector_store_returns_relevant_chunk(tmp_path) -> None:
    db_path = tmp_path / "lab.sqlite"
    embedder = HashingEmbeddingModel(dimensions=64)
    store = SQLiteVectorStore(db_path)

    chunk = Chunk(id="c1", document_id="doc", text="RAG 使用混合检索和重排序提升召回质量", metadata={"source": "doc.md"})
    store.upsert(chunk, embedder.embed(chunk.text))

    results = store.search(embedder.embed("RAG 重排序"), top_k=1)

    assert results[0].chunk.id == "c1"
    assert results[0].score > 0


def test_memory_store_retrieves_profile_and_episode(tmp_path) -> None:
    db_path = tmp_path / "lab.sqlite"
    embedder = HashingEmbeddingModel(dimensions=64)
    memory = MemoryStore(db_path, embedder)

    memory.add_profile_fact("u1", "goal", "准备 Agent 算法面试")
    memory.add_episode("u1", "我最近在复习 RAG 数据工程和向量库。")

    context = memory.retrieve_context("u1", "RAG 向量库怎么设计？")

    assert context.profile_facts[0].key == "goal"
    assert context.episodic_memories


def test_agent_runs_full_mock_chain(tmp_path) -> None:
    db_path = tmp_path / "lab.sqlite"
    embedder = HashingEmbeddingModel(dimensions=64)
    vector_store = SQLiteVectorStore(db_path)
    memory = MemoryStore(db_path, embedder)
    rag = RagEngine(vector_store, embedder)

    chunk = Chunk(id="c1", document_id="rag.md", text="RAG 包括解析、切片、向量化、检索和重排序。")
    vector_store.upsert(chunk, embedder.embed(chunk.text))

    agent = InterviewAgent(rag_engine=rag, memory_store=memory, llm=MockLLM())
    response = agent.ask("u1", "RAG 的工程链路是什么？")

    assert "MVP 模拟回答" in response.answer
    assert response.retrieved_chunks
    assert memory.recent_turns("u1")
