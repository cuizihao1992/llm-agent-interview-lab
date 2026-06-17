from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any


@dataclass(frozen=True)
class Chunk:
    id: str
    document_id: str
    text: str
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class SearchResult:
    chunk: Chunk
    score: float


@dataclass(frozen=True)
class DialogueTurn:
    user_id: str
    role: str
    content: str
    created_at: datetime = field(default_factory=lambda: datetime.now(UTC))


@dataclass(frozen=True)
class ProfileFact:
    user_id: str
    key: str
    value: str
    confidence: float = 0.7
    evidence: str = ""
    updated_at: datetime = field(default_factory=lambda: datetime.now(UTC))


@dataclass(frozen=True)
class EpisodicMemory:
    user_id: str
    content: str
    score: float = 0.0
    metadata: dict[str, Any] = field(default_factory=dict)
    created_at: datetime = field(default_factory=lambda: datetime.now(UTC))


@dataclass(frozen=True)
class MemoryContext:
    recent_turns: list[DialogueTurn]
    profile_facts: list[ProfileFact]
    episodic_memories: list[EpisodicMemory]


@dataclass(frozen=True)
class AgentResponse:
    answer: str
    retrieved_chunks: list[SearchResult]
    memory_context: MemoryContext
