#!/usr/bin/env python3
from pathlib import Path


def ensure_tag_trigger(path: Path) -> None:
    text = path.read_text()
    if "push:\n" in text and "tags:" in text:
        return

    if "on:" not in text:
        raise SystemExit(f"Missing 'on:' in {path}")

    lines = text.splitlines()
    out = []
    inserted = False
    for line in lines:
        out.append(line)
        if line.strip() == "on:":
            out.append("  push:")
            out.append("    tags:")
            out.append("      - 'v[0-9]+.[0-9]+.[0-9]+'")
            inserted = True
            break

    if not inserted:
        raise SystemExit(f"Failed to insert tag trigger in {path}")

    out.extend(lines[len(out) - 1 :])
    path.write_text("\n".join(out) + "\n")


def main() -> None:
    ensure_tag_trigger(Path(".github/workflows/rsm-docker-build.yml"))
    ensure_tag_trigger(Path(".github/workflows/rsm-podman-build.yml"))


if __name__ == "__main__":
    main()
