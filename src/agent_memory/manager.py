from .schema import DialogueTurn, EpisodicMemory, MemoryContext, ProfileFact


class MemoryManager:
    """Coordinates short-term, profile, and episodic memory."""

    def __init__(self, max_recent_turns: int = 12) -> None:
        self.max_recent_turns = max_recent_turns
        self._recent_turns: list[DialogueTurn] = []
        self._profile_facts: list[ProfileFact] = []
        self._episodic_memories: list[EpisodicMemory] = []

    def add_turn(self, turn: DialogueTurn) -> None:
        self._recent_turns.append(turn)
        self._recent_turns = self._recent_turns[-self.max_recent_turns :]

    def add_profile_fact(self, fact: ProfileFact) -> None:
        self._profile_facts.append(fact)

    def add_episodic_memory(self, memory: EpisodicMemory) -> None:
        self._episodic_memories.append(memory)

    def build_context(self, query: str) -> MemoryContext:
        # TODO: replace simple slicing with semantic retrieval over episodic memory.
        _ = query
        return MemoryContext(
            profile_facts=self._profile_facts,
            episodic_memories=self._episodic_memories[-5:],
            recent_turns=self._recent_turns,
        )

    def update_async(self, latest_turns: list[DialogueTurn]) -> None:
        # TODO: run fact extraction, conflict merge, vector upsert, and forgetting policy.
        _ = latest_turns

