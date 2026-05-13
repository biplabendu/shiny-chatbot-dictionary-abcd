#!/usr/bin/env bash
# Remove built artifacts so they get regenerated on the next ./setup.sh run.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Built artifacts (embeddings + ONNX model) ---
echo "Artifacts to delete:"
echo "  $REPO_DIR/data/embeddings/"
echo "  $REPO_DIR/python/model/"
read -r -p "Delete artifacts? [y/N] " confirm_emb
if [[ "$confirm_emb" == "y" || "$confirm_emb" == "Y" ]]; then
  rm -rf \
    "$REPO_DIR/data/embeddings" \
    "$REPO_DIR/python/model"
  echo "Deleted. Run ./setup.sh to rebuild."
else
  echo "Skipped."
fi

echo ""

# --- Python virtualenv ---
echo "Python environment to delete:"
echo "  $REPO_DIR/python_env/"
read -r -p "Delete Python environment? [y/N] " confirm_py
if [[ "$confirm_py" == "y" || "$confirm_py" == "Y" ]]; then
  rm -rf "$REPO_DIR/python_env"
  echo "Deleted. Run ./setup.sh to rebuild."
else
  echo "Skipped."
fi
