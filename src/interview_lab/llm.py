import json
import os
import urllib.request
from typing import Protocol


class LLMClient(Protocol):
    def chat(self, messages: list[dict[str, str]]) -> str:
        ...


class MockLLM:
    """Deterministic local LLM placeholder for MVP tests and demos."""

    def chat(self, messages: list[dict[str, str]]) -> str:
        user_message = messages[-1]["content"] if messages else ""
        context_hint = ""
        for message in messages:
            if message["role"] == "system" and "RAG_CONTEXT" in message["content"]:
                context_hint = "我会基于已检索到的知识片段回答。"
                break
        return f"{context_hint}\n\nMVP 模拟回答：{user_message[:500]}"


class OpenAICompatibleLLM:
    """OpenAI-compatible chat completion client using only the standard library."""

    def __init__(
        self,
        api_key: str | None = None,
        model: str | None = None,
        base_url: str | None = None,
        timeout: int = 60,
    ) -> None:
        self.api_key = api_key or os.getenv("OPENAI_API_KEY")
        self.model = model or os.getenv("OPENAI_MODEL", "gpt-4.1-mini")
        self.base_url = (base_url or os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1")).rstrip("/")
        self.timeout = timeout
        if not self.api_key:
            raise ValueError("OPENAI_API_KEY is required for OpenAICompatibleLLM")

    def chat(self, messages: list[dict[str, str]]) -> str:
        payload = json.dumps({"model": self.model, "messages": messages}).encode("utf-8")
        request = urllib.request.Request(
            f"{self.base_url}/chat/completions",
            data=payload,
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=self.timeout) as response:
            data = json.loads(response.read().decode("utf-8"))
        return data["choices"][0]["message"]["content"]
