import json
import re
import sqlite3
from pathlib import Path

from .embeddings import HashingEmbeddingModel, cosine_similarity
from .models import DialogueTurn, EpisodicMemory, MemoryContext, ProfileFact


class MemoryStore:
    """Persistent layered memory for a single-user or small-team MVP."""

    def __init__(self, db_path: str | Path, embedding_model: HashingEmbeddingModel) -> None:
        self.db_path = Path(db_path)
        self.embedding_model = embedding_model
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_schema()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.db_path)
        connection.row_factory = sqlite3.Row
        return connection

    def _init_schema(self) -> None:
        with self._connect() as connection:
            connection.executescript(
                """
                create table if not exists dialogue_turns (
                    id integer primary key autoincrement,
                    user_id text not null,
                    role text not null,
                    content text not null,
                    created_at text not null default current_timestamp
                );

                create table if not exists profile_facts (
                    id integer primary key autoincrement,
                    user_id text not null,
                    fact_key text not null,
                    fact_value text not null,
                    confidence real not null,
                    evidence text not null,
                    updated_at text not null default current_timestamp
                );

                create table if not exists episodic_memories (
                    id integer primary key autoincrement,
                    user_id text not null,
                    content text not null,
                    metadata text not null,
                    embedding text not null,
                    created_at text not null default current_timestamp
                );
                """
            )

    def add_turn(self, user_id: str, role: str, content: str) -> None:
        with self._connect() as connection:
            connection.execute(
                "insert into dialogue_turns (user_id, role, content) values (?, ?, ?)",
                (user_id, role, content),
            )

    def add_profile_fact(
        self,
        user_id: str,
        key: str,
        value: str,
        confidence: float = 0.7,
        evidence: str = "",
    ) -> None:
        with self._connect() as connection:
            connection.execute(
                """
                insert into profile_facts (user_id, fact_key, fact_value, confidence, evidence)
                values (?, ?, ?, ?, ?)
                """,
                (user_id, key, value, confidence, evidence),
            )

    def add_episode(self, user_id: str, content: str, metadata: dict | None = None) -> None:
        embedding = self.embedding_model.embed(content)
        with self._connect() as connection:
            connection.execute(
                """
                insert into episodic_memories (user_id, content, metadata, embedding)
                values (?, ?, ?, ?)
                """,
                (
                    user_id,
                    content,
                    json.dumps(metadata or {}, ensure_ascii=False),
                    json.dumps(embedding),
                ),
            )

    def retrieve_context(
        self,
        user_id: str,
        query: str,
        recent_turns: int = 8,
        top_facts: int = 8,
        top_episodes: int = 5,
    ) -> MemoryContext:
        return MemoryContext(
            recent_turns=self.recent_turns(user_id, limit=recent_turns),
            profile_facts=self.profile_facts(user_id, limit=top_facts),
            episodic_memories=self.search_episodes(user_id, query, top_k=top_episodes),
        )

    def recent_turns(self, user_id: str, limit: int = 8) -> list[DialogueTurn]:
        with self._connect() as connection:
            rows = connection.execute(
                """
                select user_id, role, content, created_at
                from dialogue_turns
                where user_id = ?
                order by id desc
                limit ?
                """,
                (user_id, limit),
            ).fetchall()
        return [
            DialogueTurn(user_id=row["user_id"], role=row["role"], content=row["content"])
            for row in reversed(rows)
        ]

    def profile_facts(self, user_id: str, limit: int = 8) -> list[ProfileFact]:
        with self._connect() as connection:
            rows = connection.execute(
                """
                select user_id, fact_key, fact_value, confidence, evidence
                from profile_facts
                where user_id = ?
                order by updated_at desc, id desc
                limit ?
                """,
                (user_id, limit),
            ).fetchall()
        return [
            ProfileFact(
                user_id=row["user_id"],
                key=row["fact_key"],
                value=row["fact_value"],
                confidence=float(row["confidence"]),
                evidence=row["evidence"],
            )
            for row in rows
        ]

    def search_episodes(self, user_id: str, query: str, top_k: int = 5) -> list[EpisodicMemory]:
        query_embedding = self.embedding_model.embed(query)
        candidates: list[EpisodicMemory] = []
        with self._connect() as connection:
            rows = connection.execute(
                """
                select user_id, content, metadata, embedding
                from episodic_memories
                where user_id = ?
                """,
                (user_id,),
            ).fetchall()

        for row in rows:
            embedding = json.loads(row["embedding"])
            score = cosine_similarity(query_embedding, embedding)
            candidates.append(
                EpisodicMemory(
                    user_id=row["user_id"],
                    content=row["content"],
                    score=score,
                    metadata=json.loads(row["metadata"]),
                )
            )
        return sorted(candidates, key=lambda item: item.score, reverse=True)[:top_k]

    def update_from_user_message(self, user_id: str, content: str) -> None:
        self.add_episode(user_id, content, metadata={"source": "user_message"})
        for key, value in self._extract_candidate_facts(content):
            self.add_profile_fact(user_id, key, value, confidence=0.6, evidence=content)

    def _extract_candidate_facts(self, content: str) -> list[tuple[str, str]]:
        patterns = [
            ("identity", r"我是([^，。；\n]+)"),
            ("preference", r"我喜欢([^，。；\n]+)"),
            ("goal", r"我的目标是([^，。；\n]+)"),
            ("current_focus", r"我正在([^，。；\n]+)"),
            ("learning_need", r"我想学习([^，。；\n]+)"),
        ]
        facts: list[tuple[str, str]] = []
        for key, pattern in patterns:
            for match in re.finditer(pattern, content):
                value = match.group(1).strip()
                if value:
                    facts.append((key, value))
        return facts

