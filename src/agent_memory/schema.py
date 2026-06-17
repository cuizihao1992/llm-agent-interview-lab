from dataclasses import dataclass, field
from datetime import datetime
from typing import Any


@dataclass(frozen=True)
class DialogueTurn:
    role: str
    content: str
    created_at: datetime = field(default_factory=datetime.utcnow)


@dataclass(frozen=True)
class ProfileFact:
    key: str
    value: str
    confidence: float
    evidence: str
    updated_at: datetime = field(default_factory=datetime.utcnow)


@dataclass(frozen=True)
class EpisodicMemory:
    content: str
    metadata: dict[str, Any] = field(default_factory=dict)
    created_at: datetime = field(default_factory=datetime.utcnow)


@dataclass(frozen=True)
class MemoryContext:
    profile_facts: list[ProfileFact]
    episodic_memories: list[EpisodicMemory]
    recent_turns: list[DialogueTurn]

