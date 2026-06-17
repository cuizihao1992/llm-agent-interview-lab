def estimate_attention_cost(sequence_length: int) -> int:
    """Return the relative O(n^2) attention cost for a sequence length."""
    if sequence_length < 0:
        raise ValueError("sequence_length must be non-negative")
    return sequence_length * sequence_length


def estimate_kv_cache_tokens(sequence_length: int, concurrent_requests: int) -> int:
    """Return a simple token-level proxy for KV cache pressure."""
    if sequence_length < 0:
        raise ValueError("sequence_length must be non-negative")
    if concurrent_requests < 0:
        raise ValueError("concurrent_requests must be non-negative")
    return sequence_length * concurrent_requests

