from .schema import Chunk, SearchResult


class InMemoryRetriever:
    """Simple keyword retriever used as a development placeholder."""

    def __init__(self) -> None:
        self._chunks: list[Chunk] = []

    def add_chunks(self, chunks: list[Chunk]) -> None:
        self._chunks.extend(chunks)

    def search(self, query: str, top_k: int = 5) -> list[SearchResult]:
        query_terms = {term.lower() for term in query.split() if term.strip()}
        results: list[SearchResult] = []

        for chunk in self._chunks:
            text = chunk.text.lower()
            score = sum(1 for term in query_terms if term in text)
            if score > 0:
                results.append(SearchResult(chunk=chunk, score=float(score)))

        return sorted(results, key=lambda item: item.score, reverse=True)[:top_k]

