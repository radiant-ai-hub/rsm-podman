#!/usr/bin/env python3
"""Minimal notebook smoke runner for the RSM container integration tests."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def code_cells(notebook: Path) -> list[str]:
    data = json.loads(notebook.read_text(encoding="utf-8"))
    return [
        "".join(cell.get("source", []))
        for cell in data.get("cells", [])
        if cell.get("cell_type") == "code"
    ]


def notebook_language(notebook: Path) -> str:
    data = json.loads(notebook.read_text(encoding="utf-8"))
    language = data.get("metadata", {}).get("language_info", {}).get("name", "")
    kernel_language = data.get("metadata", {}).get("kernelspec", {}).get("language", "")
    return (language or kernel_language or "").lower()


def shell_cell_is_browser_only(source: str) -> bool:
    commands = []
    for line in source.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        commands.append(stripped)
    return bool(commands) and all(command.startswith("open ") for command in commands)


def run_bash_notebook(notebook: Path) -> None:
    for index, source in enumerate(code_cells(notebook), start=1):
        if shell_cell_is_browser_only(source):
            print(f"SKIP {notebook.name} cell {index}: browser-only command")
            continue
        print(f"RUN  {notebook.name} cell {index}")
        subprocess.run(["bash", "-lc", source], check=True)


def run_python_notebook(notebook: Path) -> None:
    namespace: dict[str, object] = {"__name__": "__main__"}
    for index, source in enumerate(code_cells(notebook), start=1):
        print(f"RUN  {notebook.name} cell {index}")
        code = compile(source, f"{notebook}:cell-{index}", "exec")
        exec(code, namespace)


def run_notebook(notebook: Path) -> None:
    language = notebook_language(notebook)
    if language in {"bash", "sh", "shell", "shellscript"}:
        run_bash_notebook(notebook)
    elif language == "python":
        run_python_notebook(notebook)
    else:
        raise SystemExit(f"Unsupported notebook language for {notebook}: {language!r}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("notebooks", nargs="+", type=Path)
    args = parser.parse_args()

    for notebook in args.notebooks:
        if not notebook.exists():
            raise SystemExit(f"Notebook not found: {notebook}")
        print(f"=== {notebook} ===")
        run_notebook(notebook)

    return 0


if __name__ == "__main__":
    sys.exit(main())
