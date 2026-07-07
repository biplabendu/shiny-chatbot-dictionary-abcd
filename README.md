---
title: Shiny Chatbot Dictionary Abcd
emoji: 📚
colorFrom: blue
colorTo: yellow
sdk: docker
pinned: false
license: lgpl-3.0
---

# ABCD Dictionary Search

Semantic search over the [ABCD Study](https://abcdstudy.org/) data dictionary. Type a phrase like *"screen time on weekends"* or *"BMI"* — the app returns the variables in the dictionary whose labels mean roughly the same thing, ranked by cosine similarity.

**App:** <http://www.beepboopstats.com/abcd-dictionary/>

**Documentation:** [biplabendu.github.io/shiny-chatbot-dictionary-abcd](https://biplabendu.github.io/shiny-chatbot-dictionary-abcd/)

## Quickstart

```bash
git clone https://github.com/biplabendu/shiny-chatbot-dictionary-abcd.git
cd shiny-chatbot-dictionary-abcd

# Place the active dictionary parquet in data/ first (see data/Readme.md).
# Its filename must match dictionary.parquet in config.yml.
./setup.sh           # one-time: build python_env, download model, bake artifacts
./run.sh             # start the app on http://127.0.0.1:4444
```

Re-run `./setup.sh` whenever `config.yml`, `requirements.txt`, or the dictionary parquet changes.

> Tested on macOS. Requires Python 3.12 and R ≥ 4.5 on `PATH` (the scripts will offer to install them via Homebrew if missing).

## Switching ABCD releases

To update the dictionary, edit `config.yml` to point `dictionary.parquet` at a different file in `data/`, then re-run `./setup.sh`. The app reads the version from the filename at startup (`dd-abcd-7_0.parquet` → `7.0`) and shows it in the title bar and header banner.

```yaml
dictionary:
  parquet: dd-abcd-7_0.parquet
  text_column: label
  metadata_column: domain
```

## Deploying to shinyapps.io

The deploy script verifies prerequisites, cross-checks `data/embeddings/manifest.txt` against `config.yml`, previews the bundle, and runs `rsconnect::deployApp` with manifest-based Python provisioning. See [Deployment](https://biplabendu.github.io/shiny-chatbot-dictionary-abcd/deployment/) for the full walkthrough and troubleshooting tips.

```bash
# One-time, in R:
#   rsconnect::setAccountInfo(name=..., token=..., secret=...)
./deploy.sh
```

## How it works

The app is R Shiny on top of a Python search backend, bridged by [reticulate](https://rstudio.github.io/reticulate/). Queries are encoded with [MiniLM-L6-v2](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2) quantized to ONNX int8 (~23 MB, runs on CPU via [onnxruntime](https://onnxruntime.ai/)). Corpus embeddings are precomputed at build time as fp16 NumPy arrays, so runtime search reduces to a single matrix multiply. The dictionary table for the UI is stored as Parquet and read by [`nanoparquet`](https://nanoparquet.r-lib.org/). A top-level `config.yml` is the single source of truth for `setup.sh`, `python/build_embeddings.py`, and `app.R`. The embeddings carry a `manifest.txt` recording which Parquet file they were built against — if they drift, the app refuses to start. See [How it works](https://biplabendu.github.io/shiny-chatbot-dictionary-abcd/how-it-works/) for the full pipeline.

## Repo layout

```
config.yml                  single source of truth (Python version, model, dictionary release)
app.R                       Shiny UI + reticulate bridge — reads config.yml
.Rprofile                   activates renv locally; deferred to manifest on shinyapps.io
requirements.txt            Python runtime deps (onnxruntime, tokenizers, numpy)
renv.lock                   R package versions
Dockerfile                  container definition for Hugging Face Spaces
mkdocs.yml                  documentation site config (deployed to GitHub Pages)

www/
  app.css                   app styling (layout, brand polish, responsive rules)
  app.js                    client-side behavior (search shortcuts, tour, mobile, copy)

python/
  backend.py                semantic_search() — runtime
  build_embeddings.py       reads config.yml; bakes model + .npy + .npz + manifest.txt
  model/                    ONNX model + tokenizer (downloaded by setup.sh)

data/
  dd-abcd-6_0.parquet       dictionary release 6.0 (snappy-compressed)
  dd-abcd-7_0.parquet       dictionary release 7.0 (snappy-compressed)
  embeddings/               *.npy (fp16 embeddings) + *.npz (metadata) + manifest.txt
  Readme.md                 instructions for obtaining and placing dictionary files
  *.csv                     raw source CSVs — gitignored, build inputs only

setup.sh                    one-time: build python_env, download model, bake artifacts
run.sh                      start the app locally on http://127.0.0.1:4444
deploy.sh                   verify prerequisites and deploy to shinyapps.io
clean_artifacts.sh          remove generated artifacts (embeddings, python_env)

docs/                       documentation source (MkDocs, deployed to GitHub Pages)
```

## Versions

Available releases: `dd-abcd-6_0.parquet`, `dd-abcd-7_0.parquet` (latest: **7.0**).

<details>
<summary>Bundle size and memory comparison (6.0 → 7.0)</summary>

### Bundled data on disk (`data/`)

| File                      |     6.0      |     7.0      |          Δ |
| ------------------------- | -----------: | -----------: | ---------: |
| `dd-abcd-*.parquet`       | 6.75 MB      | 5.01 MB      | −1.74 MB   |
| `embeddings_imag.npy`     | 60.94 MB     | 68.63 MB     | +7.69 MB   |
| `embeddings_noimag.npy`   | 19.55 MB     | 27.15 MB     | +7.60 MB   |
| `metadata_imag.npz`       | 0.64 MB      | 0.77 MB      | +0.13 MB   |
| `metadata_noimag.npz`     | 0.26 MB      | 0.39 MB      | +0.13 MB   |
| **Total bundled data**    | **88.14 MB** | **101.95 MB** | **+13.81 MB (+15.7%)** |

The 7.0 parquet is smaller despite containing more rows (fewer columns retained / better compression).

### Embedding matrices in RAM

Each corpus is loaded entirely into memory at startup as a matrix of vector embeddings; the table shows how the size of those matrices changed between releases.

| Corpus | 6.0 shape    | 7.0 shape    | Row Δ              | RAM Δ    |
| ------ | ------------ | ------------ | ------------------ | -------- |
| imag   | 83,206 × 384 | 93,699 × 384 | +10,493 (+12.6%)   | +7.69 MB |
| noimag | 26,692 × 384 | 37,068 × 384 | +10,376 (+38.9%)   | +7.60 MB |

Resident memory for the embedding matrices increases by ~**15.3 MB**. Additional runtime memory (the parquet held in R, per-row UI structures) scales roughly with row count but was not measured here.

**Bottom line:** moving from 6.0 to 7.0 adds ~14 MB to the deployed bundle (88 → 102 MB) and ~15 MB to embedding RAM, driven by 12.6% more imaging rows and 38.9% more non-imaging rows.

</details>

## License

MIT. See [LICENSE](LICENSE).
