from .schema import Document


class DocumentIngestor:
    """Loads and normalizes source documents."""

    def load_markdown(self, document_id: str, text: str, metadata: dict | None = None) -> Document:
        normalized_text = text.strip()
        return Document(id=document_id, text=normalized_text, metadata=metadata or {})

    def clean(self, document: Document) -> Document:
        # TODO: remove boilerplate, ads, malformed characters, and duplicated sections.
        return document

