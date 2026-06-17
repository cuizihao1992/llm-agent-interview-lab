from pathlib import Path

from .embeddings import HashingEmbeddingModel
from .llm import LLMClient, MockLLM
from .memory import MemoryStore
from .models import AgentResponse, MemoryContext, SearchResult
from .rag import RagEngine
from .vector_store import SQLiteVectorStore


SYSTEM_PROMPT = """你是一个大模型 Agent 算法面试教练。
回答时必须围绕知识库和用户记忆展开，优先给出结构化、可面试表达的答案。
如果检索上下文不足，要明确说明不确定点，不要编造来源。"""


class InterviewAgent:
    def __init__(
        self,
        rag_engine: RagEngine,
        memory_store: MemoryStore,
        llm: LLMClient | None = None,
    ) -> None:
        self.rag_engine = rag_engine
        self.memory_store = memory_store
        self.llm = llm or MockLLM()

    @classmethod
    def from_db_path(cls, db_path: str | Path, llm: LLMClient | None = None) -> "InterviewAgent":
        embedding_model = HashingEmbeddingModel()
        vector_store = SQLiteVectorStore(db_path)
        memory_store = MemoryStore(db_path, embedding_model)
        rag_engine = RagEngine(vector_store, embedding_model)
        return cls(rag_engine=rag_engine, memory_store=memory_store, llm=llm)

    def ask(self, user_id: str, question: str, top_k: int = 5) -> AgentResponse:
        memory_context = self.memory_store.retrieve_context(user_id=user_id, query=question)
        retrieved = self.rag_engine.retrieve(question, top_k=top_k)
        messages = self._build_messages(question, memory_context, retrieved)
        answer = self.llm.chat(messages)

        self.memory_store.add_turn(user_id, "user", question)
        self.memory_store.add_turn(user_id, "assistant", answer)
        self.memory_store.update_from_user_message(user_id, question)

        return AgentResponse(answer=answer, retrieved_chunks=retrieved, memory_context=memory_context)

    def _build_messages(
        self,
        question: str,
        memory_context: MemoryContext,
        retrieved: list[SearchResult],
    ) -> list[dict[str, str]]:
        profile = "\n".join(f"- {fact.key}: {fact.value}" for fact in memory_context.profile_facts) or "无"
        episodes = "\n".join(
            f"- {memory.content} (score={memory.score:.3f})" for memory in memory_context.episodic_memories
        ) or "无"
        recent = "\n".join(f"{turn.role}: {turn.content}" for turn in memory_context.recent_turns) or "无"
        rag_context = "\n\n".join(
            f"[{index + 1}] source={result.chunk.metadata.get('source', result.chunk.document_id)} score={result.score:.3f}\n{result.chunk.text}"
            for index, result in enumerate(retrieved)
        ) or "无"

        system = f"""{SYSTEM_PROMPT}

PROFILE_MEMORY:
{profile}

EPISODIC_MEMORY:
{episodes}

RECENT_DIALOGUE:
{recent}

RAG_CONTEXT:
{rag_context}
"""
        return [
            {"role": "system", "content": system},
            {"role": "user", "content": question},
        ]

