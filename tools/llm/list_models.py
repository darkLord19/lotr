#!/usr/bin/env python3
"""List Anthropic models on OpenRouter with context length and pricing ($ per 1M tokens)."""
from __future__ import annotations

import json
import urllib.request

URL = "https://openrouter.ai/api/v1/models"


def per_million(price: str | None) -> str:
    try:
        return f"{float(price or 0) * 1_000_000:.2f}"
    except ValueError:
        return "?"


def main() -> None:
    with urllib.request.urlopen(URL, timeout=30) as resp:
        models: list[dict] = json.load(resp)["data"]
    rows = sorted((m for m in models if m["id"].startswith("anthropic/")), key=lambda m: m["id"])
    print(f"{'slug':48} {'context':>8} {'in $/M':>8} {'out $/M':>8}")
    for m in rows:
        p = m.get("pricing", {})
        print(f"{m['id']:48} {m.get('context_length', 0):>8} {per_million(p.get('prompt')):>8} {per_million(p.get('completion')):>8}")


if __name__ == "__main__":
    main()
