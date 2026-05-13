# Deployment

[TOC]

## Prerequisites

- A shinyapps.io account ([free tier](https://www.shinyapps.io/admin/#/signup) is fine).
- The artifacts produced by `./setup.sh` (see [Local development](local-development.md)).

## One-time: register your token

1. Sign in at [shinyapps.io](https://www.shinyapps.io) and go to **Account → Tokens → Show**.
2. Copy the `rsconnect::setAccountInfo(...)` snippet.
3. Run it in R:

    ```bash
    Rscript -e "rsconnect::setAccountInfo(name='<acct>', token='<TOKEN>', secret='<SECRET>')"
    ```

4. Verify:

    ```bash
    Rscript -e "rsconnect::accounts()"
    ```

## Deploying

```bash
./deploy.sh
```

What it does:

1. Verifies `Rscript`, the `rsconnect` package, and your configured account.
2. Cleans `python/__pycache__/` (rsconnect's hardcoded `__pycache__/` exclusion has a [trailing-slash bug](troubleshooting.md#pycache-leaks)).
3. Checks all 13 required deploy artifacts exist.
4. Calls `rsconnect::listDeploymentFiles()` and prints a bundle preview (top 10 files by size + total). Expected: **~16 files, ~116 MB**.
5. Asks for confirmation (skipped if stdin isn't a TTY).
6. Calls:

    ```r
    rsconnect::deployApp(
      appName = 'abcd-dictionary',
      appTitle = 'ABCD Dictionary Search',
      account = 'biplabendu',
      python = 'python_env/bin/python',   # <-- key: captures Python in manifest
      forceUpdate = TRUE,
      launch.browser = FALSE
    )
    ```

Configurable via env vars:

```bash
APP_NAME=abcd-dict-staging APP_TITLE='ABCD (staging)' ./deploy.sh
SHINYAPPS_ACCOUNT=myaccount ./deploy.sh                    # multi-account case
```

## How Python is provisioned on shinyapps.io

This is the part most reticulate users get stuck on. The model that works in 2026:

1. `deployApp(python = ...)` tells `rsconnect` to write a `python` section into `manifest.json` with the local Python version + a pointer to `requirements.txt`.
2. shinyapps.io's Connect runtime ignores the manifest's Python info at build time (a quirk of the free tier) — so we **don't rely on it**.
3. At runtime, `app.R` calls `reticulate::py_require(readLines("requirements.txt"))` before `source_python()`. This triggers reticulate's `uv`-based auto-installer, which:

    - Downloads `uv` (~1 s)
    - Downloads a pre-built CPython 3.12 tarball from Posit's mirror (~2 s, 32.5 MB)
    - Resolves and installs all packages in `requirements.txt` (~5 s, ~30 MB total)

The whole boot — R packages, Python install, package install, ONNX model load — takes about **16 seconds** on a fresh instance. Subsequent boots reuse the cached Python+packages.

!!! note "Earlier failures"

    Before settling on this approach we tried two patterns that *don't* work on the shinyapps.io free tier:

    - `reticulate::install_python(version = "3.12.7")` — uses pyenv to **build Python from source** on the server. Takes 5–10 minutes; shinyapps.io kills the app after ~100 seconds. Avoid.
    - Pre-setting `RETICULATE_PYTHON` in `.Rprofile` and creating the venv in `app.R` (the [ranikay shiny-reticulate-app](https://github.com/ranikay/shiny-reticulate-app) pattern from ~2019) — works only if Connect has `python3` on `PATH`, which the modern shinyapps.io does not.

## What ships and what doesn't

Controlled by `.rscignore` (top level) and `data/.rscignore` (per-subdir). rsconnect uses **exact-string `setdiff()`** against directory listings, not gitignore-style globs — so trailing slashes and nested paths don't match. See [Troubleshooting](troubleshooting.md#-rscignore-isn-t-honoring-my-patterns).

Top-level `.rscignore` excludes:

- `sanity-chks/`, `.claude/`, `.dockerignore`, `Dockerfile`, `fly.toml`
- `setup.sh`, `run.sh`, `deploy.sh`, `clean_embeddings_pythonpkgs.sh`
- `*.Rproj`, `.RData`
- Root-level duplicate / dummy CSVs

`data/.rscignore` excludes the three source CSVs (build inputs only; the runtime uses Parquet and `.npy`/`.npz`).

Final deploy bundle: **16 files, 116 MB**, with the largest items being the imaging-corpus embedding (64 MB), the ONNX model (23 MB), and the noimag embedding (20 MB).

## Watching the deploy

After `./deploy.sh` finishes, tail server logs:

```bash
Rscript -e "rsconnect::showLogs(appName='abcd-dictionary', account='biplabendu', streaming=TRUE)"
```

A healthy first boot looks like:

```
shinyapps[...]: Shiny application starting ...
shinyapps[...]: Attaching package: 'dplyr'
shinyapps[...]: Attaching package: 'bslib'
shinyapps[...]: Downloading uv...Done!
shinyapps[...]: Downloading cpython-3.12.13-linux-x86_64-gnu (32.5MiB)
shinyapps[...]:  Downloaded cpython-3.12.13-linux-x86_64-gnu
shinyapps[...]: Downloading numpy (15.9MiB)
shinyapps[...]: Downloading tokenizers (3.2MiB)
shinyapps[...]: Downloading onnxruntime (17.3MiB)
shinyapps[...]: Installed 27 packages in 5.40s
shinyapps[...]: Listening on http://127.0.0.1:35131
```

If the log streams stop *before* "Listening on…", see [Troubleshooting](troubleshooting.md).

## Sanity-checking the bundle before deploying

`deploy.sh` already prints a preview, but you can also run it standalone:

```r
Rscript -e '
  files <- rsconnect::listDeploymentFiles(".")
  sizes <- file.info(files)$size
  cat(sprintf("%d files, %.1f MB\n", length(files), sum(sizes)/1e6))
  for (i in order(-sizes)) cat(sprintf("  %7.2f MB  %s\n", sizes[i]/1e6, files[i]))
'
```

Confirm no raw CSVs, `sanity-chks/`, `python/__pycache__/`, or `.RData` appear. If something leaks, add the **exact directory entry name** (no trailing slash, no nested path) to `.rscignore`.

## Updating the deployed app

Deployments are versioned by shinyapps.io. Every `./deploy.sh` invocation:

- Uploads a new bundle
- Builds a new container image (~1 min for unchanged R deps; longer if `renv.lock` changed)
- Performs a rolling restart (`deploying: Starting instances` → `terminating: Stopping old instances`)

Users connected to the old version stay on it until they reload.
