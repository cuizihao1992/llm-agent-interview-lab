import argparse
import re
import sys
from pathlib import Path

from .agent import InterviewAgent
from .embeddings import HashingEmbeddingModel
from .llm import MockLLM, OpenAICompatibleLLM
from .memory import MemoryStore
from .rag import RagEngine
from .vector_store import SQLiteVectorStore


DEFAULT_DB = Path("data/interview_lab.sqlite")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="LLM Agent Interview Lab MVP CLI")
    parser.add_argument("--db", default=str(DEFAULT_DB), help="SQLite database path")

    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("init-db", help="Initialize local SQLite database")

    index_parser = subparsers.add_parser("index-docs", help="Index markdown docs into the vector store")
    index_parser.add_argument("--docs", default="docs", help="Markdown docs directory")
    index_parser.add_argument("--clear", action="store_true", help="Clear existing RAG chunks before indexing")

    ask_parser = subparsers.add_parser("ask", help="Ask the interview agent")
    ask_parser.add_argument("question", help="Question to ask")
    ask_parser.add_argument("--user", default="local-user", help="User id for memory isolation")
    ask_parser.add_argument("--top-k", type=int, default=5, help="RAG chunks to retrieve")
    ask_parser.add_argument("--real-llm", action="store_true", help="Use OpenAI-compatible API instead of MockLLM")

    chat_parser = subparsers.add_parser("chat", help="Start an interactive chat session")
    chat_parser.add_argument("--user", default="local-user", help="User id for memory isolation")
    chat_parser.add_argument("--real-llm", action="store_true", help="Use OpenAI-compatible API instead of MockLLM")

    fact_parser = subparsers.add_parser("add-fact", help="Add a structured profile memory fact")
    fact_parser.add_argument("--user", default="local-user", help="User id")
    fact_parser.add_argument("--key", required=True, help="Fact key")
    fact_parser.add_argument("--value", required=True, help="Fact value")

    view_parser = subparsers.add_parser("view-doc", help="Render a markdown file in the terminal")
    view_parser.add_argument("path", help="Markdown file path")
    view_parser.add_argument("--plain", action="store_true", help="Print raw markdown without terminal formatting")

    return parser


def _configure_stdout() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")


def _render_inline_markdown(text: str) -> str:
    text = re.sub(r"`([^`]+)`", r"\1", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"\1", text)
    text = re.sub(r"\*([^*]+)\*", r"\1", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    return text


def _print_markdown(path: Path, *, plain: bool = False) -> None:
    _configure_stdout()
    content = path.read_text(encoding="utf-8")
    if plain:
        print(content)
        return

    in_code_block = False
    for raw_line in content.splitlines():
        line = raw_line.rstrip()
        stripped = line.strip()

        if stripped.startswith("```"):
            in_code_block = not in_code_block
            print("    " + stripped)
            continue

        if in_code_block:
            print("    " + line)
            continue

        heading = re.match(r"^(#{1,6})\s+(.+)$", stripped)
        if heading:
            level = len(heading.group(1))
            title = _render_inline_markdown(heading.group(2))
            prefix = "=" if level <= 2 else "-"
            print()
            print(title)
            print(prefix * min(len(title), 72))
            continue

        if stripped.startswith(">"):
            print("  | " + _render_inline_markdown(stripped.lstrip("> ")))
            continue

        bullet = re.match(r"^(\s*)([-*+]|\d+\.)\s+(.+)$", line)
        if bullet:
            indent = " " * (len(bullet.group(1)) // 2 * 2)
            print(f"{indent}- {_render_inline_markdown(bullet.group(3))}")
            continue

        print(_render_inline_markdown(line))


def main() -> None:
    args = build_parser().parse_args()
    db_path = Path(args.db)
    embedding_model = HashingEmbeddingModel()
    vector_store = SQLiteVectorStore(db_path)
    memory_store = MemoryStore(db_path, embedding_model)
    rag_engine = RagEngine(vector_store, embedding_model)

    if args.command == "init-db":
        print(f"Initialized database: {db_path}")
        return

    if args.command == "index-docs":
        if args.clear:
            vector_store.clear()
        count = rag_engine.index_markdown_dir(args.docs)
        print(f"Indexed {count} chunks from {args.docs}. Total chunks: {vector_store.count()}")
        return

    if args.command == "add-fact":
        memory_store.add_profile_fact(args.user, args.key, args.value, confidence=0.95, evidence="manual")
        print(f"Added fact for {args.user}: {args.key}={args.value}")
        return

    if args.command == "view-doc":
        _print_markdown(Path(args.path), plain=args.plain)
        return

    llm = OpenAICompatibleLLM() if getattr(args, "real_llm", False) else MockLLM()
    agent = InterviewAgent(rag_engine=rag_engine, memory_store=memory_store, llm=llm)

    if args.command == "ask":
        response = agent.ask(args.user, args.question, top_k=args.top_k)
        print(response.answer)
        print("\nSources:")
        for result in response.retrieved_chunks:
            source = result.chunk.metadata.get("source", result.chunk.document_id)
            print(f"- {source} score={result.score:.3f}")
        return

    if args.command == "chat":
        print("LLM Agent Interview Lab chat. Type 'exit' to quit.")
        while True:
            question = input("\nYou> ").strip()
            if question.lower() in {"exit", "quit"}:
                break
            if not question:
                continue
            response = agent.ask(args.user, question)
            print(f"\nAgent> {response.answer}")


if __name__ == "__main__":
    main()
