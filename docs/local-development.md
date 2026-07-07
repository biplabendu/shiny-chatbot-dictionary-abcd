# Local development

[TOC]

## Prerequisites

- **macOS or Linux** (tested on macOS Sequoia / arm64)
- **Python** at the version named in `config.yml` (`python_version`, currently `3.12`) on `PATH`
- **R 4.5+** on `PATH`
- The active ABCD data-dictionary parquet in `data/`. The filename is set in
  `config.yml` under `dictionary.parquet` (currently `dd-abcd-7_0.parquet`).
  See [`data/Readme.md`](https://github.com/biplabendu/shiny-chatbot-dictionary-abcd/blob/main/data/Readme.md)
  for how to produce it from `NBDCtools::get_dd_abcd()`.

`setup.sh` and `run.sh` will offer to install Python and R via Homebrew if they're missing.

## config.yml — the single source of truth

`config.yml` at the repo root drives the whole pipeline. Live contents:

```yaml
--8<-- "config.yml"
```

Everything that varies between releases or experiments lives here:

| Key | What it controls | Read by |
|---|---|---|
| `python_version` | Interpreter version required for the venv (X.Y) | `setup.sh` |
| `venv_dir` | Path to the local Python virtualenv | `setup.sh`, `.Rprofile` (indirectly) |
| `model.repo_id` | HuggingFace repo for the embedding model | `python/build_embeddings.py` |
| `model.onnx_hub_path` | ONNX weights file inside that repo | `python/build_embeddings.py` |
| `model.max_seq_len`, `model.batch_size` | Encoder limits at build time | `python/build_embeddings.py` |
| `dictionary.parquet` | Active dictionary release (filename in `data/`) | `setup.sh`, `build_embeddings.py`, `app.R` |
| `dictionary.text_column` | Column whose text gets encoded into embeddings | `python/build_embeddings.py` |
| `dictionary.metadata_column` | Column kept alongside each embedding for filtering | `python/build_embeddings.py`, `python/backend.py` |

Switching ABCD releases is therefore a one-line edit (`dictionary.parquet:`) followed by `./setup.sh`. The R UI parses the version out of the filename (`dd-abcd-7_0.parquet` → `7.0`) and shows it in the title and header banner.

## One-time setup

```bash
./setup.sh
```

What it does (see `setup.sh` for the full source):

1. Reads `python_version` and `venv_dir` from `config.yml` and verifies that interpreter is on `PATH`.
2. Creates the venv (rebuilds it if the existing one is the wrong Python version) and installs `requirements.txt` + build-only deps (`pandas`, `fastparquet`, `huggingface_hub`, `pyyaml`).
3. Runs `python/build_embeddings.py`, which:
    - Downloads the ONNX model + tokenizer named in `config.yml` from Hugging Face into `python/model/` (skipped if already present).
    - Reads `data/<dictionary.parquet>` and derives both corpora **in-memory**: `imag` (every row with a non-null `text_column`) and `noimag` (`imag` minus rows where `metadata_column == "Imaging"`).
    - Encodes each corpus to fp16 NumPy arrays and writes `data/embeddings/embeddings_<x>.npy`.
    - Writes a tiny `data/embeddings/metadata_<x>.npz` per corpus with the metadata + label arrays the backend needs at runtime.
    - Writes `data/embeddings/manifest.txt` recording the parquet filename the embeddings were built against (the R UI checks this on startup).
4. Runs `renv::restore()` and installs `nanoparquet` if missing.

Re-run `./setup.sh` any time:

- `config.yml` changes (different dictionary release, different model, different columns)
- `requirements.txt` changes
- The dictionary parquet itself changes
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

1. Checks the configured Python version + R are present (offers `brew install` if not).
2. Checks the artifact paths exist (`python_env/`, `python/model/`, `data/embeddings/`, the active `data/<dictionary>.parquet`). If anything's missing, offers to run `./setup.sh`.
3. Execs `Rscript -e "shiny::runApp(host=..., port=..., launch.browser=TRUE)"`.

The `exec` means Ctrl+C goes straight to R, which exits cleanly.

On startup, `app.R` performs two integrity checks before serving requests:

1. The parquet named in `config.yml` exists at `data/<that-filename>`.
2. `data/embeddings/manifest.txt` matches `config.yml`. If you bump the release in `config.yml` but forget to re-run `./setup.sh`, the app refuses to start with an explicit error rather than silently displaying stale rows from the previous release.

## What runs where

| Component | Source | Where it lives at runtime |
|---|---|---|
| R Shiny UI | `app.R` | R session started by `run.sh` |
| Python backend | `python/backend.py` | Python venv at `python_env/` (local) or shinyapps.io's managed venv |
| ONNX model + tokenizer | `python/model/{model.onnx, tokenizer.json}` | Loaded lazily on first search |
| Corpus embeddings | `data/embeddings/embeddings_*.npy` (fp16) | Loaded into RAM as fp32 on first search per corpus |
| Domain + label arrays | `data/embeddings/metadata_*.npz` | Loaded with `np.load(allow_pickle=True)` |
| Drift guard | `data/embeddings/manifest.txt` | Read once at app startup |
| Dictionary for display | `data/<dictionary.parquet>` (from `config.yml`) | Read by `nanoparquet::read_parquet()` at app startup |

`.Rprofile` handles the local-vs-shinyapps split:

```r
if (Sys.info()[["user"]] != "shiny" && dir.exists("python_env")) {
  Sys.setenv(RETICULATE_PYTHON = file.path(getwd(), "python_env", "bin", "python"))
}
```

On shinyapps.io, `Sys.info()[["user"]] == "shiny"` is true, the local block is skipped, and reticulate's auto-installer takes over (see [Deployment](deployment.md)).

## Cleaning up

`./clean_artifacts.sh` interactively removes `data/embeddings/`, `python/model/`, and/or `python_env/`. Pair it with `./setup.sh` to rebuild from scratch:

```bash
./clean_artifacts.sh    # answer 'y' to both prompts
./setup.sh                          # full rebuild (~3 min)
```

## Re-running just the embedding build

If only the parquet changed (not the model or requirements):

```bash
python_env/bin/python python/build_embeddings.py
```

The model files are skipped if already present; only the embeddings, metadata, and manifest get rewritten.

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
