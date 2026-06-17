from .schema import Chunk, Document


class SemanticChunker:
    """Placeholder semantic chunker with overlap support."""

    def __init__(self, chunk_size: int = 500, overlap_ratio: float = 0.15) -> None:
        self.chunk_size = chunk_size
        self.overlap_ratio = overlap_ratio

    def split(self, document: Document) -> list[Chunk]:
        # TODO: replace character splitting with heading/paragraph-aware semantic splitting.
        if not document.text:
            return []

        overlap = int(self.chunk_size * self.overlap_ratio)
        step = max(1, self.chunk_size - overlap)
        chunks: list[Chunk] = []

        for index, start in enumerate(range(0, len(document.text), step)):
            text = document.text[start : start + self.chunk_size]
            if not text:
                continue
            chunks.append(
                Chunk(
                    id=f"{document.id}_chunk_{index}",
                    document_id=document.id,
                    text=text,
                    metadata=document.metadata,
                )
            )

        return chunks

