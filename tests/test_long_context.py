from long_context.analysis import estimate_attention_cost, estimate_kv_cache_tokens


def test_estimate_attention_cost() -> None:
    assert estimate_attention_cost(128) == 16384


def test_estimate_kv_cache_tokens() -> None:
    assert estimate_kv_cache_tokens(4096, 8) == 32768

