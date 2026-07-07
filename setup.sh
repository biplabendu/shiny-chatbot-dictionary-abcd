#!/usr/bin/env bash
# setup.sh — one-shot environment + artifact build for the ABCD dictionary Shiny app.
#
# Steps:
#   1. Verify the Python version named in config.yml is available.
#   2. (Re)create the venv (path from config.yml) and install runtime + build deps.
#   3. Run python/build_embeddings.py to produce, from data/<dictionary.parquet>:
#         python/model/{model.onnx,tokenizer.json}
#         data/embeddings/embeddings_*.npy
#         data/embeddings/metadata_*.npz
#         data/embeddings/manifest.txt
#   4. Restore R packages via renv (installs nanoparquet et al.).
#
# Re-run any time config.yml, requirements.txt, or the dictionary parquet change.

set -euo pipefail

cd "$(dirname "$0")"

CONFIG=config.yml
[[ -f "$CONFIG" ]] || { printf "config.yml not found in %s\n" "$PWD" >&2; exit 1; }

# Tiny YAML reader for unique top-level scalar keys — used before the venv
# exists, so we can't depend on pyyaml here. Strips quotes and inline comments.
yaml_top() {
  awk -v key="$1" '
    $1 == key":" {
      sub(/^[^:]+:[[:space:]]*/, "")
      sub(/[[:space:]]*#.*$/, "")
      gsub(/^["'\'']|["'\'']$/, "")
      print; exit
    }
  ' "$CONFIG"
}

PY_VERSION=$(yaml_top python_version)
VENV=$(yaml_top venv_dir)
[[ -n "$PY_VERSION" ]] || { echo "config.yml: python_version missing" >&2; exit 1; }
[[ -n "$VENV"       ]] || { echo "config.yml: venv_dir missing"       >&2; exit 1; }

PY=${PYTHON:-python${PY_VERSION}}

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

section "1. Python toolchain"
if ! command -v "$PY" >/dev/null; then
  die "$PY not found on PATH. Install Python $PY_VERSION (e.g. \`brew install python@$PY_VERSION\`) or set PYTHON=<path>."
fi
PY_VER=$("$PY" -c 'import sys; print("%d.%d" % sys.version_info[:2])')
if [[ "$PY_VER" != "$PY_VERSION" ]]; then
  die "Expected Python $PY_VERSION (from config.yml), found $PY_VER at $(command -v "$PY")."
fi
ok "$PY ($("$PY" --version))"

section "2. Python virtualenv"
# Ensure the venv is in .gitignore so it never gets tracked
if ! grep -qs "^$VENV/" .gitignore; then
  echo "" >> .gitignore
  echo "$VENV/" >> .gitignore
  ok "Added $VENV/ to .gitignore"
fi
if [[ -d "$VENV" ]]; then
  EXISTING_VER=$("$VENV/bin/python" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo "?")
  if [[ "$EXISTING_VER" != "$PY_VERSION" ]]; then
    warn "Existing $VENV is Python $EXISTING_VER — removing"
    rm -rf "$VENV"
  fi
fi
if [[ ! -d "$VENV" ]]; then
  "$PY" -m venv "$VENV"
  ok "created $VENV"
fi

"$VENV/bin/python" -m pip install --quiet --upgrade pip
# Runtime deps (shipped to shinyapps.io) + build-only deps
# (pandas, fastparquet, huggingface_hub, pyyaml for reading config.yml).
"$VENV/bin/python" -m pip install --quiet -r requirements.txt
"$VENV/bin/python" -m pip install --quiet pandas fastparquet huggingface_hub pyyaml
ok "Python deps installed"

# Now that pyyaml is available, resolve config values needed for messages.
FULL_PARQUET=$("$VENV/bin/python" -c "import yaml; print(yaml.safe_load(open('$CONFIG'))['dictionary']['parquet'])")

section "3. Build artifacts (model + embeddings)"
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
ok "Python $PY_VERSION venv  -> $VENV/"
ok "Model files       -> python/model/"
ok "Embeddings + meta -> data/embeddings/"
ok "Dictionary table  -> data/$FULL_PARQUET"
printf "\nRun the app locally:  ${bold}./run.sh${reset}\n"
