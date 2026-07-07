# Reference

[TOC]

Links to every external resource the project depends on — grouped by role.

## Project and data

| Resource | Link |
|---|---|
| This project | [biplabendu/shiny-chatbot-dictionary-abcd](https://github.com/biplabendu/shiny-chatbot-dictionary-abcd) |
| ABCD Study | [abcdstudy.org](https://abcdstudy.org/) |
| NBDCtools (ABCD data access) | [nbdc-datahub/ABCDtools](https://github.com/nbdc-datahub/ABCDtools) |

## Semantic model

| Resource | Link |
|---|---|
| all-MiniLM-L6-v2 | [sentence-transformers/all-MiniLM-L6-v2](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2) on HuggingFace |
| ONNX int8 weights (AVX2) | same repo, path `onnx/model_quint8_avx2.onnx` |

## R packages

| Package | Role in the app | GitHub |
|---|---|---|
| shiny | Web application framework | [rstudio/shiny](https://github.com/rstudio/shiny) |
| reticulate | R–Python bridge | [rstudio/reticulate](https://github.com/rstudio/reticulate) |
| reactable | Interactive results table | [glin/reactable](https://github.com/glin/reactable) |
| bslib | Bootstrap UI theming | [rstudio/bslib](https://github.com/rstudio/bslib) |
| nanoparquet | Reads the Parquet dictionary | [r-lib/nanoparquet](https://github.com/r-lib/nanoparquet) |
| fontawesome | Icons in buttons | [rstudio/fontawesome](https://github.com/rstudio/fontawesome) |
| cicerone | Guided onboarding tour (driver.js wrapper) | [JohnCoene/cicerone](https://github.com/JohnCoene/cicerone) |
| dplyr | Data manipulation | [tidyverse/dplyr](https://github.com/tidyverse/dplyr) |
| stringr | String cleaning | [tidyverse/stringr](https://github.com/tidyverse/stringr) |
| yaml | Reads `config.yml` at app startup | [vubiostat/r-yaml](https://github.com/vubiostat/r-yaml) |
| jsonlite | Serializes the hidden-column lists passed to the client-side JS | [jeroen/jsonlite](https://github.com/jeroen/jsonlite) |
| htmlwidgets | Embeds reactable's row-click JS handler | [ramnathv/htmlwidgets](https://github.com/ramnathv/htmlwidgets) |

## Python packages — runtime

These are installed automatically on first deploy via `reticulate::py_require()` + `uv`.

| Package | Role | GitHub |
|---|---|---|
| onnxruntime | Runs the ONNX model at query time | [microsoft/onnxruntime](https://github.com/microsoft/onnxruntime) |
| tokenizers | Fast Rust-backed query tokenizer | [huggingface/tokenizers](https://github.com/huggingface/tokenizers) |
| numpy | Embedding arrays and cosine matmul | [numpy/numpy](https://github.com/numpy/numpy) |

## Python packages — build-time only

Used by `python/build_embeddings.py` to produce the pre-assembled artifacts. Not shipped to the deployed app.

| Package | Role | GitHub |
|---|---|---|
| huggingface_hub | Downloads model weights from HuggingFace | [huggingface/huggingface_hub](https://github.com/huggingface/huggingface_hub) |
| pandas | Reads the dictionary Parquet at build time | [pandas-dev/pandas](https://github.com/pandas-dev/pandas) |
| fastparquet | Pandas engine used to read the dictionary Parquet | [dask/fastparquet](https://github.com/dask/fastparquet) |
| PyYAML | Parses `config.yml` (model + dictionary settings) | [yaml/pyyaml](https://github.com/yaml/pyyaml) |

## Deployment tooling

| Resource | Link |
|---|---|
| shinyapps.io | [shinyapps.io](https://www.shinyapps.io/) |
| rsconnect | [rstudio/rsconnect](https://github.com/rstudio/rsconnect) |
| uv (Python package manager) | [astral-sh/uv](https://github.com/astral-sh/uv) |

## Documentation

| Resource | Link |
|---|---|
| MkDocs | [mkdocs/mkdocs](https://github.com/mkdocs/mkdocs) |
| pymdownx extensions | [facelessuser/pymdown-extensions](https://github.com/facelessuser/pymdown-extensions) |
| Mermaid (diagrams) | [mermaid-js/mermaid](https://github.com/mermaid-js/mermaid) |
