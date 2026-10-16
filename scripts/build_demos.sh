#!/usr/bin/env bash
# Build each folder in contents/demos into a JupyterLite site (Pyodide kernel) at the same
# path in _site. Run after `quarto render`; the publish workflow calls this script.
# Needs jupyterlite-core, jupyterlite-pyodide-kernel, jupyter_server, pip, and git.
set -euo pipefail

# Notebooks install Pymablock with `%pip install pymablock`, which finds this wheel first.
# Pymablock's main branch falls back to SciPy sparse solves without MUMPS, which the browser
# lacks; release 2.2.1 needs MUMPS for the implicit method used by the quantum-dot notebook.
PYMABLOCK_REF=59d9994f9eb0c30a6ab4cb34dd7e4e1bbd69a4a4

root="$(cd "$(dirname "$0")/.." && pwd)"
wheels="$(mktemp -d)"
pip wheel --quiet --no-deps --wheel-dir "$wheels" \
  "git+https://gitlab.kwant-project.org/qt/pymablock.git@$PYMABLOCK_REF"

for demo in "$root"/contents/demos/*/; do
  # Separate build directories keep the JupyterLite build caches apart.
  (cd "$(mktemp -d)" && jupyter lite build --no-sourcemaps \
    --contents "$demo" --piplite-wheels "$wheels"/*.whl \
    --output-dir "$root/_site/${demo#"$root"/}")
done
