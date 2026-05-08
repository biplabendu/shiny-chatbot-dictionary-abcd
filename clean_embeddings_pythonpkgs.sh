#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Embeddings ---
echo "Embeddings to delete:"
echo "  $REPO_DIR/data/embeddings/"
echo "  $REPO_DIR/data/local_embeddings/"
echo "  $REPO_DIR/python/local_embeddings/"
read -r -p "Delete embeddings? [y/N] " confirm_emb
if [[ "$confirm_emb" == "y" || "$confirm_emb" == "Y" ]]; then
  rm -rf \
    "$REPO_DIR/data/embeddings" \
    "$REPO_DIR/data/local_embeddings" \
    "$REPO_DIR/python/local_embeddings"
  echo "Embeddings deleted. They will be regenerated on the first search run."
else
  echo "Skipped embeddings."
fi

echo ""

# --- Python packages ---
echo "Python environment to delete:"
echo "  $REPO_DIR/python_env/"
read -r -p "Delete Python environment? [y/N] " confirm_py
if [[ "$confirm_py" == "y" || "$confirm_py" == "Y" ]]; then
  rm -rf "$REPO_DIR/python_env"
  echo "Python environment deleted."
  echo "To rebuild:"
  echo "  python3 -m venv python_env"
  echo "  source python_env/bin/activate"
  echo "  pip install -r requirements.txt"
else
  echo "Skipped Python environment."
fi
