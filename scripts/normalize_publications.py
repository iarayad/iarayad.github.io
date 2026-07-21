"""Normalize fields produced by publist to the shared CV data convention."""

import argparse
from datetime import date
from pathlib import Path

import yaml


PUBLICATIONS = (
    Path(__file__).resolve().parents[1] / "contents" / "data" / "publications.yml"
)


def guidance_header(path: Path) -> str:
    lines = []
    for line in path.read_text().splitlines(keepends=True):
        if line.startswith("#") or (not line.strip() and lines):
            lines.append(line)
        else:
            break
    return "".join(lines).rstrip() + "\n" if lines else ""


def normalize(path: Path = PUBLICATIONS, header: str | None = None) -> None:
    if header is None:
        header = guidance_header(path)
    publications = yaml.safe_load(path.read_text())
    for publication in publications:
        publication.pop("journal_ref", None)
        publication.pop("journal_url", None)
        for field in ("id", "vol", "page"):
            if publication.get(field) is not None:
                publication[field] = str(publication[field])
        for field in ("on_arxiv", "published"):
            if isinstance(publication.get(field), str):
                publication[field] = date.fromisoformat(publication[field])

    body = yaml.safe_dump(
        publications,
        allow_unicode=True,
        default_flow_style=False,
        sort_keys=False,
    )
    path.write_text(header + body)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", nargs="?", type=Path, default=PUBLICATIONS)
    args = parser.parse_args()
    normalize(args.path.resolve())


if __name__ == "__main__":
    main()
