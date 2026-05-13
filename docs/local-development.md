# Local development

[TOC]

## Prerequisites

- **macOS or Linux** (tested on macOS Sequoia / arm64)
- **Python 3.12** on `PATH`
- **R 4.5+** on `PATH`
- The three source CSVs in `data/` (gitignored; obtain separately):
    - `data/dd-abcd-6_0.csv` (full dictionary, ~68 MB)
    - `data/dd-abcd-6_0_minimal.csv` (imaging corpus input, ~27 MB)
    - `data/dd-abcd-6_0_minimal_noimag.csv` (noimag corpus input, ~6 MB)

`setup.sh` and `run.sh` will offer to install Python and R via Homebrew if they're missing.

## One-time setup

```bash
./setup.sh
```

What it does (see `setup.sh` for the full source):

1. Verifies `python3.12` is on `PATH`.
2. Creates `python_env/` (Python 3.12 venv) and installs `requirements.txt` + build-only deps (`pandas`, `fastparquet`, `huggingface_hub`).
3. Runs `python/build_embeddings.py`, which:
    - Downloads the ONNX MiniLM int8 model + tokenizer from Hugging Face into `python/model/`.
    - Reads the two minimal CSVs, encodes labels into fp16 NumPy arrays, and writes them to `data/embeddings/`.
    - Writes a tiny `metadata_<x>.npz` per corpus with the domain + label arrays the backend needs at runtime.
    - Converts the full CSV (`data/dd-abcd-6_0.csv`) to snappy Parquet at `data/dd-abcd-6_0.parquet` (the file the R UI reads).
4. Runs `renv::restore()` and installs `nanoparquet` if missing.

Re-run `./setup.sh` any time:

- `requirements.txt` changes
- The source CSVs change (rebake the embeddings + parquet)
- You delete `python_env/` or `data/embeddings/` to start fresh

## Running the app

```bash
./run.sh
```

Defaults: `http://127.0.0.1:4444` with browser auto-launch. Configurable:

```bash
PORT=8080 ./run.sh
HOST=0.0.0.0 ./run.sh   # bind all interfaces (LAN access)
```

What it does:

1. Checks Python 3.12 + R are present (offers `brew install` if not).
2. Checks the four artifact paths exist (`python_env/`, `python/model/`, `data/embeddings/`, `data/dd-abcd-6_0.parquet`). If anything's missing, offers to run `./setup.sh`.
3. Execs `Rscript -e "shiny::runApp(host=..., port=..., launch.browser=TRUE)"`.

The `exec` means Ctrl+C goes straight to R, which exits cleanly.

## What runs where

| Component | Source | Where it lives at runtime |
|---|---|---|
| R Shiny UI | `app.R` | R session started by `run.sh` |
| Python backend | `python/backend.py` | Python venv at `python_env/` (local) or shinyapps.io's managed venv |
| ONNX model + tokenizer | `python/model/{model.onnx, tokenizer.json}` | Loaded lazily on first search |
| Corpus embeddings | `data/embeddings/embeddings_*.npy` (fp16) | mmapped via NumPy on first search |
| Domain + label arrays | `data/embeddings/metadata_*.npz` | Loaded with `np.load(allow_pickle=True)` |
| Dictionary for display | `data/dd-abcd-6_0.parquet` | Read by `nanoparquet::read_parquet()` at app startup |

`.Rprofile` handles the local-vs-shinyapps split:

```r
if (Sys.info()[["user"]] != "shiny" && dir.exists("python_env")) {
  Sys.setenv(RETICULATE_PYTHON = file.path(getwd(), "python_env", "bin", "python"))
}
```

On shinyapps.io, `Sys.info()[["user"]] == "shiny"` is true, the local block is skipped, and reticulate's auto-installer takes over (see [Deployment](deployment.md)).

## Cleaning up

`./clean_embeddings_pythonpkgs.sh` interactively removes `data/embeddings/`, `python/model/`, and/or `python_env/`. Pair it with `./setup.sh` to rebuild from scratch:

```bash
./clean_embeddings_pythonpkgs.sh    # answer 'y' to both prompts
./setup.sh                          # full rebuild (~3 min)
```

## Re-running just the embedding build

If only the CSVs changed (not the model or requirements):

```bash
python_env/bin/python python/build_embeddings.py
```

The model files are skipped if already present; only the embeddings + parquet get rebuilt.

## Editing the app interactively

The app uses `options(shiny.autoreload = TRUE)`, so saving `app.R` while it's running picks up changes on the next request. Python changes (`python/backend.py`) require restarting the app (reticulate caches loaded modules).

## Sanity-check scripts

`sanity-chks/` contains the scripts we used to evaluate embedding backends:

- `sanity_check_model2vec.py` — compares `model2vec` distilled embeddings vs MiniLM baseline
- `sanity_check_onnx.py` — compares ONNX int8 vs fp32 PyTorch baseline

Both produce side-by-side top-K results, Jaccard overlap, and a "quality ratio" metric. Useful if you want to swap in a different model.

The folder is `.gitignore`'d, `.rscignore`'d, and not deployed. Run scripts directly:

```bash
/tmp/onnx_sanity_env/bin/python sanity-chks/sanity_check_onnx.py
```

(They need their own venv since they pull `sentence-transformers` for the baseline.)
