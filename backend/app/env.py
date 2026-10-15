"""Tiny .env reader so the server can use the repo's .env without another dependency.
Existing environment variables win. Values are never logged, only names."""
import os
from pathlib import Path


def parse(text: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        if line.startswith("export "):
            line = line[len("export "):]
        key, _, value = line.partition("=")
        key, value = key.strip(), value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        elif " #" in value:
            value = value.split(" #", 1)[0].rstrip()
        if key:
            out[key] = value
    return out


def load(paths: list[Path] | None = None) -> list[str]:
    """Load the first values found, backend/.env before the repo root .env. Returns the names that were set."""
    here = Path(__file__).resolve().parent.parent
    paths = paths if paths is not None else [here / ".env", here.parent / ".env"]
    names: list[str] = []
    for p in paths:
        try:
            data = parse(p.read_text())
        except OSError:
            continue
        for k, v in data.items():
            if k not in os.environ and v != "":
                os.environ[k] = v
                names.append(k)
    return names
