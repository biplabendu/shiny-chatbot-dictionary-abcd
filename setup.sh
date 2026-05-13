#!/usr/bin/env bash
# setup.sh — one-shot environment + artifact build for the ABCD dictionary Shiny app.
#
# Steps:
#   1. Verify Python 3.12 is available.
#   2. (Re)create python_env/ on Python 3.12 and install runtime + build deps.
#   3. Run python/build_embeddings.py to produce:
#         python/model/{model.onnx,tokenizer.json}
#         data/embeddings/embeddings_*.npy
#         data/embeddings/metadata_*.npz
#         data/dd-abcd-6_0.parquet
#   4. Restore R packages via renv (installs nanoparquet et al.).
#
# Re-run any time requirements.txt or the source CSVs change.

set -euo pipefail

PY=${PYTHON:-python3.12}
VENV=python_env

# Color helpers (only when stdout is a tty).
if [[ -t 1 ]]; then
  bold=$'\033[1m'; green=$'\033[32m'; yellow=$'\033[33m'; red=$'\033[31m'; reset=$'\033[0m'
else
  bold=""; green=""; yellow=""; red=""; reset=""
fi
section() { printf "\n${bold}=== %s ===${reset}\n" "$1"; }
ok()      { printf "${green}✓${reset} %s\n" "$1"; }
warn()    { printf "${yellow}!${reset} %s\n" "$1"; }
die()     { printf "${red}✗ %s${reset}\n" "$1" >&2; exit 1; }

cd "$(dirname "$0")"

section "1. Python toolchain"
if ! command -v "$PY" >/dev/null; then
  die "$PY not found on PATH. Install Python 3.12 (e.g. \`brew install python@3.12\`) or set PYTHON=<path>."
fi
PY_VER=$("$PY" -c 'import sys; print("%d.%d" % sys.version_info[:2])')
if [[ "$PY_VER" != "3.12" ]]; then
  die "Expected Python 3.12, found $PY_VER at $(command -v "$PY")."
fi
ok "$PY ($("$PY" --version))"

section "2. Python virtualenv"
if [[ -d "$VENV" ]]; then
  EXISTING_VER=$("$VENV/bin/python" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo "?")
  if [[ "$EXISTING_VER" != "3.12" ]]; then
    warn "Existing $VENV is Python $EXISTING_VER — removing"
    rm -rf "$VENV"
  fi
fi
if [[ ! -d "$VENV" ]]; then
  "$PY" -m venv "$VENV"
  ok "created $VENV"
fi

"$VENV/bin/python" -m pip install --quiet --upgrade pip
# Runtime deps (shipped to shinyapps.io) + build-only deps (pandas, fastparquet, huggingface_hub).
"$VENV/bin/python" -m pip install --quiet -r requirements.txt
"$VENV/bin/python" -m pip install --quiet pandas fastparquet huggingface_hub
ok "Python deps installed"

section "3. Build artifacts (model + embeddings + parquet)"
"$VENV/bin/python" python/build_embeddings.py

section "4. R packages (renv)"
if ! command -v Rscript >/dev/null; then
  warn "Rscript not found — skipping R package install. Install R, then run:"
  warn "    Rscript -e 'renv::restore(); renv::install(\"nanoparquet\"); renv::snapshot()'"
else
  Rscript -e '
    if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv")
    renv::restore(prompt = FALSE)
    if (!requireNamespace("nanoparquet", quietly = TRUE)) {
      renv::install("nanoparquet", prompt = FALSE)
      renv::snapshot(prompt = FALSE)
    }
  '
  ok "R packages restored"
fi

section "Summary"
ok "Python 3.12 venv  -> $VENV/"
ok "Model files       -> python/model/"
ok "Embeddings + meta -> data/embeddings/"
ok "Dictionary table  -> data/dd-abcd-6_0.parquet"
printf "\nRun the app locally:  ${bold}Rscript -e 'shiny::runApp()'${reset}\n"
