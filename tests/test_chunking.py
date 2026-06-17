from rag_pipeline.chunking import SemanticChunker
from rag_pipeline.schema import Document


def test_chunker_splits_text_with_overlap() -> None:
    document = Document(id="doc", text="abcdef" * 100)
    chunker = SemanticChunker(chunk_size=100, overlap_ratio=0.1)

    chunks = chunker.split(document)

    assert len(chunks) > 1
    assert chunks[0].document_id == "doc"
    assert len(chunks[0].text) == 100

