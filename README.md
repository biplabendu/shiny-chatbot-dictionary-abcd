# ABCD Dictionary Search

Semantic search over the [ABCD Study](https://abcdstudy.org/) data dictionary. Type a phrase like *"screen time on weekends"* or *"BMI"* — the app returns the variables in the dictionary whose labels mean roughly the same thing, ranked by cosine similarity.

**Live demo:** [biplabendu.shinyapps.io/abcd-dictionary](https://biplabendu.shinyapps.io/abcd-dictionary/)

**Documentation:** [biplabendu.github.io/shiny-chatbot-dictionary-abcd](https://biplabendu.github.io/shiny-chatbot-dictionary-abcd/)

## How it works (in one paragraph)

The app is R Shiny on top of a Python search backend, bridged by [reticulate](https://rstudio.github.io/reticulate/). Queries are encoded with [MiniLM-L6-v2](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2) quantized to ONNX int8 (~23 MB, runs on CPU via [onnxruntime](https://onnxruntime.ai/)). Corpus embeddings are **pre-baked** to fp16 NumPy arrays at build time, so search at runtime is a single matmul. The dictionary table for the UI is stored as Parquet and read by [`nanoparquet`](https://nanoparquet.r-lib.org/). See [How it works](https://biplabendu.github.io/shiny-chatbot-dictionary-abcd/how-it-works/) for the full pipeline.

## Quickstart

Tested on macOS. Requires Python 3.12 and R ≥ 4.5 on `PATH` (the scripts will offer to install them via Homebrew if missing).

```bash
git clone https://github.com/biplabendu/shiny-chatbot-dictionary-abcd.git
cd shiny-chatbot-dictionary-abcd

# Place the source CSVs in data/ first (see data/Readme.md).
./setup.sh           # one-time: build python_env, download model, bake artifacts
./run.sh             # start the app on http://127.0.0.1:4444
```

Re-run `./setup.sh` whenever `requirements.txt` or the source CSVs change.

## Deploying to shinyapps.io

```bash
# One-time, in R:
#   rsconnect::setAccountInfo(name=..., token=..., secret=...)
./deploy.sh
```

The deploy script verifies prerequisites, previews the bundle, and runs `rsconnect::deployApp` with manifest-based Python provisioning. See [Deployment](https://biplabendu.github.io/shiny-chatbot-dictionary-abcd/deployment/) for the full walkthrough and troubleshooting tips.

## Repo layout

```
app.R                       Shiny UI + reticulate bridge
.Rprofile                   activates renv locally; deferred to manifest on shinyapps.io
requirements.txt            Python runtime deps (onnxruntime, tokenizers, numpy)
renv.lock                   R package versions

python/
  backend.py                semantic_search() — runtime
  build_embeddings.py       bakes model + .npy + .npz from the source CSVs
  model/                    ONNX model + tokenizer (downloaded by build script)

data/
  dd-abcd-6_0.parquet       UI table (full dictionary, snappy-compressed)
  embeddings/               *.npy (fp16 embeddings) + *.npz (domain + label arrays)
  *.csv                     raw source CSVs — gitignored, build inputs only

setup.sh / run.sh / deploy.sh
docs/  mkdocs.yml           documentation site (deployed to GitHub Pages)
```

## License

MIT. See [LICENSE](LICENSE).
