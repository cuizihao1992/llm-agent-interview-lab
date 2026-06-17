import re
from pathlib import Path

from .embeddings import HashingEmbeddingModel
from .models import Chunk, SearchResult
from .vector_store import SQLiteVectorStore


class SemanticMarkdownChunker:
    def __init__(self, chunk_size: int = 900, overlap: int = 120) -> None:
        if chunk_size <= 0:
            raise ValueError("chunk_size must be positive")
        if overlap < 0 or overlap >= chunk_size:
            raise ValueError("overlap must be >= 0 and smaller than chunk_size")
        self.chunk_size = chunk_size
        self.overlap = overlap

    def split(self, document_id: str, text: str, metadata: dict | None = None) -> list[Chunk]:
        sections = self._split_sections(text)
        chunks: list[Chunk] = []
        buffer = ""
        index = 0

        for section in sections:
            candidate = f"{buffer}\n\n{section}".strip() if buffer else section
            if len(candidate) <= self.chunk_size:
                buffer = candidate
                continue

            if buffer:
                chunks.append(self._chunk(document_id, index, buffer, metadata or {}))
                index += 1
                buffer = self._tail(buffer)

            while len(section) > self.chunk_size:
                part = section[: self.chunk_size]
                chunks.append(self._chunk(document_id, index, part, metadata or {}))
                index += 1
                section = self._tail(part) + section[self.chunk_size :]

            buffer = section

        if buffer:
            chunks.append(self._chunk(document_id, index, buffer, metadata or {}))

        return chunks

    def _split_sections(self, text: str) -> list[str]:
        parts = re.split(r"\n(?=#{1,6}\s)|\n\s*\n", text.strip())
        return [part.strip() for part in parts if part.strip()]

    def _tail(self, text: str) -> str:
        if self.overlap == 0:
            return ""
        return text[-self.overlap :]

    def _chunk(self, document_id: str, index: int, text: str, metadata: dict) -> Chunk:
        return Chunk(
            id=f"{document_id}::chunk-{index}",
            document_id=document_id,
            text=text.strip(),
            metadata={**metadata, "chunk_index": index},
        )


class RagEngine:
    def __init__(
        self,
        vector_store: SQLiteVectorStore,
        embedding_model: HashingEmbeddingModel,
        chunker: SemanticMarkdownChunker | None = None,
    ) -> None:
        self.vector_store = vector_store
        self.embedding_model = embedding_model
        self.chunker = chunker or SemanticMarkdownChunker()

    def index_markdown_dir(self, docs_dir: str | Path) -> int:
        docs_path = Path(docs_dir)
        if not docs_path.exists():
            raise FileNotFoundError(f"docs directory not found: {docs_path}")

        indexed = 0
        for path in sorted(docs_path.rglob("*.md")):
            text = path.read_text(encoding="utf-8")
            document_id = path.relative_to(docs_path).as_posix()
            metadata = {"source": document_id, "type": "markdown"}
            chunks = self.chunker.split(document_id=document_id, text=text, metadata=metadata)
            for chunk in chunks:
                self.vector_store.upsert(chunk, self.embedding_model.embed(chunk.text))
                indexed += 1
        return indexed

    def retrieve(self, query: str, top_k: int = 5) -> list[SearchResult]:
        candidates = self.vector_store.search(self.embedding_model.embed(query), top_k=max(top_k * 8, top_k))
        query_terms = self._terms(query)
        reranked: list[SearchResult] = []
        for result in candidates:
            text_terms = self._terms(result.chunk.text)
            lexical_score = self._lexical_score(query_terms, text_terms)
            score = (0.65 * result.score) + (0.35 * lexical_score)
            reranked.append(SearchResult(chunk=result.chunk, score=score))
        return sorted(reranked, key=lambda item: item.score, reverse=True)[:top_k]

    def build_context(self, query: str, top_k: int = 5) -> str:
        results = self.retrieve(query, top_k=top_k)
        return "\n\n".join(
            f"[source={result.chunk.metadata.get('source', result.chunk.document_id)} score={result.score:.3f}]\n{result.chunk.text}"
            for result in results
        )

    def _terms(self, text: str) -> set[str]:
        terms = set(re.findall(r"[a-zA-Z0-9]+", text.lower()))
        for segment in re.findall(r"[\u4e00-\u9fff]+", text):
            terms.add(segment)
            terms.update(segment[index : index + 2] for index in range(max(0, len(segment) - 1)))
            terms.update(segment[index : index + 3] for index in range(max(0, len(segment) - 2)))
        return terms

    def _lexical_score(self, query_terms: set[str], text_terms: set[str]) -> float:
        if not query_terms:
            return 0.0
        return len(query_terms & text_terms) / len(query_terms)
