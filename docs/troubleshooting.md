# Troubleshooting

These are real failures we hit while building and deploying this app. Useful reading if you're adapting the pattern to another reticulate-based Shiny app.

[TOC]

## App fails to start: "Suitable Python installation for creating a venv not found"

**Symptom** (server log):

```
Error in stop_no_virtualenv_starter(version = version, python = python) :
  Suitable Python installation for creating a venv not found.
  Requested Python: python3
```

**Cause:** shinyapps.io's modern Connect runtime ships **no Python interpreter by default**. The traditional `virtualenv_create(python = "python3")` pattern (from ~2019 examples) fails because nothing on `PATH` matches.

**Fix:** Don't try to call `virtualenv_create()` against a system `python3`. Use `reticulate::py_require()` instead — it triggers reticulate's `uv`-based auto-installer, which pulls a pre-built CPython tarball:

```r
reticulate::py_require(readLines("requirements.txt"))
source_python("python/backend.py")
```

## App boot loops: pyenv builds Python from source

**Symptom:**

```
Downloading Python-3.12.7.tar.xz...
Installing Python-3.12.7...
```

…then silence for ~90 seconds, then the container restarts and tries again.

**Cause:** `reticulate::install_python(version = "3.12.7")` invokes `pyenv install`, which downloads the **Python source tarball** and compiles it. Even with `optimized = FALSE`, the build takes longer than shinyapps.io's app-startup window (~100 s).

**Fix:** Remove `install_python()` from `app.R`. The new `py_require()` path uses `uv`, which downloads a **pre-built** Python binary in ~2 s. See the previous section.

## Boot succeeds but search fails: `ModuleNotFoundError: No module named 'onnxruntime'`

**Symptom:**

```
Downloading numpy (15.9MiB)
 Downloaded numpy
Installed 1 package in 69ms
Error in py_run_file_impl(file, local, convert) :
  ModuleNotFoundError: No module named 'onnxruntime'
```

**Cause:** Reticulate's auto-installer scans Python source for imports and tries to install only the packages it detects. Some import names don't match pip names (or aren't in reticulate's hardcoded mapping), so they get missed.

**Fix:** Declare dependencies explicitly **before** `source_python()`:

```r
reticulate::py_require(readLines("requirements.txt"))
source_python("python/backend.py")
```

`py_require()` adds every line of `requirements.txt` to the install list, regardless of what the scanner thinks.

## `.rscignore` isn't honoring my patterns {#-rscignore-isn-t-honoring-my-patterns}

**Symptom:** Files you listed in `.rscignore` still show up in the deploy bundle.

**Cause:** `rsconnect:::ignoreBundleFiles()` matches lines with **exact-string `setdiff()`** against the immediate contents of each directory — not gitignore-style globs:

```r
ignored <- c("rsconnect", "renv", "packrat", ".git", ".gitignore", ".svn",
             ".Rhistory", ".Rproj.user", ".DS_Store", ".quarto", "app_cache",
             "__pycache__/")
contents <- setdiff(contents, ignored)
```

Three implications:

1. **No trailing slashes.** `sanity-chks/` won't match the directory entry `sanity-chks` (no slash in `dir()` output).
2. **No nested paths.** `data/dd-abcd-6_0.csv` in a top-level `.rscignore` does nothing — `data` is the top-level entry, `dd-abcd-6_0.csv` is in the subdir. Add a `data/.rscignore`.
3. **No globs.** `*.csv` won't expand. Enumerate each file.

**Fix:** Use exact top-level names. For subdirectory exclusions, drop a `.rscignore` in that subdirectory:

```text
# .rscignore (top level)
sanity-chks
.claude
Dockerfile
setup.sh
run.sh
deploy.sh
shiny-chatbot-dictionary-abcd.Rproj
.RData

# data/.rscignore
dd-abcd-6_0.csv
dd-abcd-6_0_minimal.csv
dd-abcd-6_0_minimal_noimag.csv
```

## `__pycache__/` leaks into the bundle {#pycache-leaks}

**Symptom:** `python/__pycache__/backend.cpython-312.pyc` shows up in `rsconnect::listDeploymentFiles()` even though `__pycache__/` is in rsconnect's own hardcoded exclude list.

**Cause:** The hardcoded entry is `"__pycache__/"` *with a trailing slash*, but `dir()` returns entries without slashes — `setdiff()` exact-match fails.

**Fix:** Delete `python/__pycache__/` before listing/deploying. `deploy.sh` already does this:

```bash
find python -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
```

## App boots locally but fails on shinyapps.io with `cannot open file 'renv/activate.R'`

**Cause:** `rsconnect` excludes the entire `renv/` directory from the deploy bundle (one of the hardcoded exclusions). If `.Rprofile` does an unguarded `source("renv/activate.R")`, the app crashes on first start.

**Fix:** Make the `source()` conditional in `.Rprofile`:

```r
if (file.exists("renv/activate.R")) {
  if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv")
  source("renv/activate.R")
}
```

shinyapps.io installs R packages from `renv.lock` independently, so the activation step isn't needed on the server.

## Bundle preview shows the raw CSVs (101 MB) when they should be excluded

**Cause:** Most likely the `.rscignore` patterns are subpaths (`data/dd-abcd-6_0.csv`) in the top-level file, which don't match top-level entries. See the [.rscignore section](#-rscignore-isn-t-honoring-my-patterns).

**Fix:** Move CSV exclusions into `data/.rscignore`. Verify with:

```bash
Rscript -e '
  files <- rsconnect::listDeploymentFiles(".")
  cat(length(files), "files,", sum(file.info(files)$size)/1e6, "MB\n")
'
```

Expected: ~16 files, ~116 MB.

## "No shinyapps.io account configured"

**Cause:** You haven't run `rsconnect::setAccountInfo(...)` yet, or you're running from a different user / R library where the credentials weren't stored.

**Fix:** Get a fresh token from **shinyapps.io → Account → Tokens → Show** and paste it into an R session. The credentials persist under `~/.config/rstudio/rsconnect/` (or `~/Library/Application Support/R/rsconnect/` on macOS).

## Multiple accounts: deploy uses the wrong one

**Cause:** When more than one account is configured, `deploy.sh` errors out asking which to use.

**Fix:**

```bash
SHINYAPPS_ACCOUNT=biplabendu ./deploy.sh
```

## Quality drop after switching embedding models

If you swap MiniLM for something else, run `sanity-chks/sanity_check_onnx.py` (or write a variant) against your candidate model. Static-embedding models like `model2vec` fail badly on acronym-heavy queries (e.g. `BMI`) — we documented this in [How it works](how-it-works.md#model-choice-and-quality).

## Local R can't find `nanoparquet`

**Cause:** `renv::restore()` ran before `nanoparquet` was added to the lockfile.

**Fix:** `setup.sh` installs it automatically. To do it manually:

```bash
Rscript -e 'renv::install("nanoparquet"); renv::snapshot()'
```

## How to wipe state and rebuild

```bash
./clean_embeddings_pythonpkgs.sh   # interactive — answer y to both prompts
rm -rf python_env                  # if clean script didn't remove it
./setup.sh
./run.sh
```

This is the right sequence after upgrading `requirements.txt` or changing `python/build_embeddings.py`.
