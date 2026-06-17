import hashlib
import math
import re


class HashingEmbeddingModel:
    """Small deterministic embedding model for local MVP runs.

    It is not a semantic model. It gives the project a real vector pipeline
    without requiring network access or API keys, and can be swapped for a
    production embedding provider later.
    """

    def __init__(self, dimensions: int = 256) -> None:
        if dimensions <= 0:
            raise ValueError("dimensions must be positive")
        self.dimensions = dimensions

    def embed(self, text: str) -> list[float]:
        vector = [0.0] * self.dimensions
        for token in self._tokens(text):
            digest = hashlib.md5(token.encode("utf-8")).digest()
            index = int.from_bytes(digest[:4], "big") % self.dimensions
            sign = 1.0 if digest[4] % 2 == 0 else -1.0
            vector[index] += sign

        norm = math.sqrt(sum(value * value for value in vector))
        if norm == 0:
            return vector
        return [value / norm for value in vector]

    def _tokens(self, text: str) -> list[str]:
        words = re.findall(r"[\w\u4e00-\u9fff]+", text.lower())
        char_ngrams: list[str] = []
        compact = "".join(words)
        for size in (2, 3):
            char_ngrams.extend(compact[index : index + size] for index in range(max(0, len(compact) - size + 1)))
        return words + char_ngrams


def cosine_similarity(left: list[float], right: list[float]) -> float:
    if len(left) != len(right):
        raise ValueError("vectors must have the same length")
    return sum(a * b for a, b in zip(left, right))

