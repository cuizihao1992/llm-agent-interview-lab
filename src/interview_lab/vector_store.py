import json
import sqlite3
from pathlib import Path
from typing import Any

from .embeddings import cosine_similarity
from .models import Chunk, SearchResult


class SQLiteVectorStore:
    """A tiny persistent vector store backed by SQLite.

    This MVP uses a linear scan, which is fine for a small interview knowledge
    base. The interface is intentionally close to what Qdrant, Milvus, Chroma,
    or pgvector adapters would need later.
    """

    def __init__(self, db_path: str | Path, table_name: str = "rag_chunks") -> None:
        self.db_path = Path(db_path)
        self.table_name = table_name
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_schema()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.db_path)
        connection.row_factory = sqlite3.Row
        return connection

    def _init_schema(self) -> None:
        with self._connect() as connection:
            connection.execute(
                f"""
                create table if not exists {self.table_name} (
                    id text primary key,
                    document_id text not null,
                    text text not null,
                    metadata text not null,
                    embedding text not null
                )
                """
            )

    def upsert(self, chunk: Chunk, embedding: list[float]) -> None:
        with self._connect() as connection:
            connection.execute(
                f"""
                insert into {self.table_name} (id, document_id, text, metadata, embedding)
                values (?, ?, ?, ?, ?)
                on conflict(id) do update set
                    document_id = excluded.document_id,
                    text = excluded.text,
                    metadata = excluded.metadata,
                    embedding = excluded.embedding
                """,
                (
                    chunk.id,
                    chunk.document_id,
                    chunk.text,
                    json.dumps(chunk.metadata, ensure_ascii=False),
                    json.dumps(embedding),
                ),
            )

    def search(
        self,
        query_embedding: list[float],
        top_k: int = 5,
        metadata_filter: dict[str, Any] | None = None,
    ) -> list[SearchResult]:
        if top_k <= 0:
            return []

        results: list[SearchResult] = []
        with self._connect() as connection:
            rows = connection.execute(f"select * from {self.table_name}").fetchall()

        for row in rows:
            metadata = json.loads(row["metadata"])
            if metadata_filter and not self._metadata_matches(metadata, metadata_filter):
                continue

            embedding = json.loads(row["embedding"])
            score = cosine_similarity(query_embedding, embedding)
            results.append(
                SearchResult(
                    chunk=Chunk(
                        id=row["id"],
                        document_id=row["document_id"],
                        text=row["text"],
                        metadata=metadata,
                    ),
                    score=score,
                )
            )

        return sorted(results, key=lambda item: item.score, reverse=True)[:top_k]

    def count(self) -> int:
        with self._connect() as connection:
            row = connection.execute(f"select count(*) as count from {self.table_name}").fetchone()
        return int(row["count"])

    def clear(self) -> None:
        with self._connect() as connection:
            connection.execute(f"delete from {self.table_name}")

    def _metadata_matches(self, metadata: dict[str, Any], expected: dict[str, Any]) -> bool:
        return all(metadata.get(key) == value for key, value in expected.items())

