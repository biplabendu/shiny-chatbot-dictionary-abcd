#!/usr/bin/env bash
# deploy.sh — deploy the ABCD dictionary Shiny app to shinyapps.io.
#
# One-time setup (run in R, not here):
#   1. Sign in at https://www.shinyapps.io > Account > Tokens > Show.
#   2. Copy the rsconnect::setAccountInfo(...) snippet.
#   3. Paste it into:  Rscript -e "rsconnect::setAccountInfo(...)"
#
# Then run this script. Configurable via env vars:
#   APP_NAME=abcd-dictionary  APP_TITLE='ABCD Dictionary Search'
#   SHINYAPPS_ACCOUNT=<account>  (auto-detected if only one configured)

set -euo pipefail

cd "$(dirname "$0")"

if [[ -t 1 ]]; then
  bold=$'\033[1m'; green=$'\033[32m'; yellow=$'\033[33m'; red=$'\033[31m'; reset=$'\033[0m'
else
  bold=""; green=""; yellow=""; red=""; reset=""
fi
ok()      { printf "${green}✓${reset} %s\n" "$1"; }
warn()    { printf "${yellow}!${reset} %s\n" "$1"; }
die()     { printf "${red}✗ %s${reset}\n" "$1" >&2; exit 1; }
section() { printf "\n${bold}=== %s ===${reset}\n" "$1"; }

APP_NAME=${APP_NAME:-abcd-dictionary}
APP_TITLE=${APP_TITLE:-"ABCD Dictionary Search"}
ACCOUNT=${SHINYAPPS_ACCOUNT:-}

section "1. Checking R"
command -v Rscript >/dev/null 2>&1 || die "Rscript not found. Run ./run.sh first to install R."
ok "R found"

section "2. Checking rsconnect package"
if ! Rscript -e 'if (!requireNamespace("rsconnect", quietly=TRUE)) quit(status=1)' >/dev/null 2>&1; then
  warn "rsconnect not installed — installing now"
  Rscript -e 'install.packages("rsconnect", repos="https://cloud.r-project.org")'
fi
ok "rsconnect installed"

section "3. Checking shinyapps.io account"
# Sentinel-extract the account name — Rscript stdout is contaminated by
# renv's "project is out-of-sync" message and our .Rprofile's startup
# diagnostics. Take only the line matching the marker.
ACCOUNTS=$(Rscript -e '
  a <- tryCatch(rsconnect::accounts(), error = function(e) NULL)
  if (!is.null(a) && nrow(a) > 0) cat("__ACCOUNTS__=", paste(a$name, collapse=","), "\n", sep="")
' 2>/dev/null | sed -n 's/^__ACCOUNTS__=//p')
if [[ -z "$ACCOUNTS" ]]; then
  die "No shinyapps.io account configured.
   Go to https://www.shinyapps.io > Account > Tokens > Show, copy the
   rsconnect::setAccountInfo(...) snippet, and run:
       Rscript -e \"rsconnect::setAccountInfo(name='<acct>', token='<TOKEN>', secret='<SECRET>')\""
fi
if [[ -z "$ACCOUNT" ]]; then
  if [[ "$ACCOUNTS" != *,* ]]; then
    ACCOUNT="$ACCOUNTS"
  else
    die "Multiple accounts configured ($ACCOUNTS). Set SHINYAPPS_ACCOUNT=<name> and re-run."
  fi
fi
ok "Account: $ACCOUNT"

section "4. Checking deploy artifacts"
[[ -f config.yml ]] || die "config.yml not found."
# config.yml is the single source of truth for which dictionary release ships.
PARQUET=$(sed -n 's/^[[:space:]]*parquet:[[:space:]]*\([^[:space:]#]*\).*/\1/p' config.yml | head -n 1)
[[ -n "$PARQUET" ]] || die "Could not parse dictionary.parquet from config.yml"
ok "Active dictionary: ${PARQUET}"

required=(
  app.R
  .Rprofile
  .rscignore
  config.yml
  requirements.txt
  renv.lock
  python/backend.py
  python/model/model.onnx
  python/model/tokenizer.json
  "data/${PARQUET}"
  data/embeddings/manifest.txt
  data/embeddings/embeddings_noimag.npy
  data/embeddings/embeddings_imag.npy
  data/embeddings/metadata_noimag.npz
  data/embeddings/metadata_imag.npz
)
missing=()
for f in "${required[@]}"; do
  [[ -f "$f" ]] || missing+=("$f")
done
if (( ${#missing[@]} > 0 )); then
  die "Missing artifacts: ${missing[*]}. Run ./setup.sh first."
fi

# app.R refuses to start if manifest.txt disagrees with config.yml — catch
# that here so we don't ship a bundle that crashes on boot.
BUILT=$(head -n 1 data/embeddings/manifest.txt | tr -d '[:space:]')
if [[ "$BUILT" != "$PARQUET" ]]; then
  die "Embeddings/config drift: config.yml points to '${PARQUET}' but embeddings were built for '${BUILT}'. Run ./setup.sh."
fi

ok "${#required[@]} required files present, manifest in sync"

section "5. Bundle preview (what rsconnect would upload)"
# rsconnect's hardcoded "__pycache__/" exclusion has a trailing-slash bug
# (setdiff exact match), so caches leak through. Nuke them first.
find python -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
# Drop any non-active dictionary parquet and any raw release CSVs that
# leaked into the bundle. .rscignore can't express "all but the active
# release" (no globs), so the filter lives here next to the config read.
Rscript -e "
files <- rsconnect::listDeploymentFiles('.')
keep_parquet <- 'data/${PARQUET}'
is_other_parquet <- grepl('^data/dd-abcd-.*[.]parquet\$', files) & files != keep_parquet
is_release_csv <- grepl('^(data/)?dd-abcd-.*[.]csv\$', files)
files <- files[!is_other_parquet & !is_release_csv]
sizes <- file.info(files)\$size
total_mb <- sum(sizes, na.rm = TRUE) / 1e6
cat(sprintf('  %d files, %.1f MB total\n', length(files), total_mb))
cat('\n  Top files by size:\n')
ord <- order(-sizes)[seq_len(min(10, length(files)))]
for (i in ord) cat(sprintf('    %7.2f MB  %s\n', sizes[i] / 1e6, files[i]))
if (total_mb > 1024) cat(sprintf('\n  WARNING: bundle is %.1f MB — shinyapps.io free tier caps at 1 GB.\n', total_mb))
"

section "6. Confirm"
if [[ -t 0 ]]; then
  printf "Deploy '${bold}%s${reset}' (title '${bold}%s${reset}') to account '${bold}%s${reset}'? [y/N] " \
    "$APP_NAME" "$APP_TITLE" "$ACCOUNT"
  read -r confirm
  confirm=$(printf "%s" "$confirm" | tr '[:upper:]' '[:lower:]')
  [[ "$confirm" == "y" || "$confirm" == "yes" ]] || die "Aborted."
else
  warn "Non-interactive shell — proceeding without confirmation"
fi

section "7. Deploying"
ok "First deploy takes 5–15 minutes (installs R + Python deps on the server)."
ok "Subsequent deploys are faster (caches are reused)."
echo
exec Rscript -e "
files <- rsconnect::listDeploymentFiles('.')
keep_parquet <- 'data/${PARQUET}'
is_other_parquet <- grepl('^data/dd-abcd-.*[.]parquet\$', files) & files != keep_parquet
is_release_csv <- grepl('^(data/)?dd-abcd-.*[.]csv\$', files)
files <- files[!is_other_parquet & !is_release_csv]
rsconnect::deployApp(
  appDir = '.',
  appFiles = files,
  appName = '${APP_NAME}',
  appTitle = '${APP_TITLE}',
  account = '${ACCOUNT}',
  python = 'python_env/bin/python',
  forceUpdate = TRUE,
  launch.browser = FALSE
)"
