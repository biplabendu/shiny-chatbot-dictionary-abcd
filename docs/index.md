# ABCD Dictionary Search

Semantic search over the [ABCD Study](https://abcdstudy.org/) data dictionary. Type a phrase like *"screen time on weekends"* or *"BMI"* — the app returns the variables in the dictionary whose labels mean roughly the same thing, ranked by cosine similarity.

**[Live demo →](https://biplabendu.shinyapps.io/abcd-dictionary/)**  
**[Source on GitHub →](https://github.com/biplabendu/shiny-chatbot-dictionary-abcd)**

## What it is

A small **R Shiny** app with a **Python** search backend, bridged by [reticulate](https://rstudio.github.io/reticulate/). It is designed to deploy on the shinyapps.io free tier under tight resource limits (1 GB bundle, 1 GB RAM, short startup window). To keep the bundle and startup time small, the heavy lifting happens **offline at build time**, not at runtime:

- Corpus embeddings are pre-computed once with [MiniLM-L6-v2](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2), L2-normalized, and saved as `float16` NumPy arrays.
- The MiniLM model is quantized to ONNX `int8` (~23 MB) so it runs on plain [onnxruntime](https://onnxruntime.ai/) with no `torch`.
- The dictionary table is stored as Parquet (smaller and faster than the source CSV) and read by [`nanoparquet`](https://nanoparquet.r-lib.org/) in R.

At runtime, each search is a tokenize → ONNX inference → single matmul → top-K sort. Typical query latency is well under 100 ms.

## Current build configuration

`config.yml` at the repo root is the **single source of truth** for the build pipeline (`setup.sh`, `python/build_embeddings.py`) and the R app (`app.R`). Switching ABCD releases or embedding models is a one-line edit followed by `./setup.sh`. The values below are read directly from the live file:

```yaml
--8<-- "config.yml"
```

`app.R` reads the same file at startup and refuses to launch if `data/embeddings/manifest.txt` (written by the build) disagrees with `dictionary.parquet` — the UI cannot silently display the wrong dictionary version.

## Where to go next

- **[Using the app](using-the-app.md)** — Search, filters, row details, CSV export, and the NBDCtools handoff.
- **[How it works](how-it-works.md)** — Architecture diagram, file layout, and a walkthrough of a single search from keystroke to results table.
- **[Local development](local-development.md)** — `setup.sh`, `run.sh`, and `config.yml` — what they do and how to extend them when source data or dependencies change.
- **[Deployment](deployment.md)** — `deploy.sh` walkthrough, what the shinyapps.io manifest does, and how Python is provisioned on the server.
- **[Troubleshooting](troubleshooting.md)** — Real failures we hit during deployment and how we fixed them — useful reading if you're adapting this to your own reticulate-based app.
