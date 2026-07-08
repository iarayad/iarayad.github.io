from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
CONTENTS = ROOT / "contents"
SOURCE = CONTENTS / "data"


def load_yaml(path):
    with path.open() as f:
        return yaml.safe_load(f)


def update_home():
    home = load_yaml(SOURCE / "home.yml")
    path = CONTENTS / "home.qmd"
    new = f"💻 {home['phd_line']}"
    text = path.read_text()
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if line.startswith("💻 "):
            lines[index] = new
            path.write_text("\n".join(lines) + "\n")
            return
    if new not in text:
        raise RuntimeError("Could not find the PhD line in contents/home.qmd")


def main():
    update_home()


if __name__ == "__main__":
    main()
