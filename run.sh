#!/usr/bin/env bash
# run.sh — launch the ABCD dictionary Shiny app from the CLI (no RStudio needed).
#
# Checks Python 3.12 and R are installed, offers to install them if missing,
# then runs ./setup.sh to build artifacts (if needed) and starts the app.

set -euo pipefail

cd "$(dirname "$0")"

if [[ -t 1 ]]; then
  bold=$'\033[1m'; green=$'\033[32m'; yellow=$'\033[33m'; red=$'\033[31m'; reset=$'\033[0m'
else
  bold=""; green=""; yellow=""; red=""; reset=""
fi
ok()    { printf "${green}✓${reset} %s\n" "$1"; }
warn()  { printf "${yellow}!${reset} %s\n" "$1"; }
die()   { printf "${red}✗ %s${reset}\n" "$1" >&2; exit 1; }

prompt_yn() {
  # Default: No. Returns 0 if user answered yes.
  local q="$1" reply
  if [[ ! -t 0 ]]; then
    warn "Non-interactive shell — defaulting to 'no' for: $q"
    return 1
  fi
  printf "%s [y/N] " "$q"
  read -r reply || return 1
  reply=$(printf "%s" "$reply" | tr '[:upper:]' '[:lower:]')
  [[ "$reply" == "y" || "$reply" == "yes" ]]
}

OS=$(uname -s)

install_or_die() {
  local label="$1" check_cmd="$2" brew_cmd="$3" linux_hint="$4" manual_hint="$5"
  if eval "$check_cmd" >/dev/null 2>&1; then
    ok "$label found"
    return
  fi
  warn "$label is not installed."
  case "$OS" in
    Darwin)
      if ! command -v brew >/dev/null 2>&1; then
        die "Homebrew not found. Install $label manually: $manual_hint"
      fi
      if prompt_yn "Install $label via '$brew_cmd'?"; then
        eval "$brew_cmd"
      else
        die "$label is required to run the app."
      fi
      ;;
    Linux)
      die "$label not found. Install it ($linux_hint), then re-run."
      ;;
    *)
      die "Unsupported OS ($OS). Install $label manually: $manual_hint"
      ;;
  esac
}

printf "${bold}=== 1. Checking Python 3.12 ===${reset}\n"
install_or_die "Python 3.12" \
  "command -v python3.12" \
  "brew install python@3.12" \
  "e.g. 'sudo apt-get install python3.12'" \
  "https://www.python.org/downloads/release/python-3120/"

printf "\n${bold}=== 2. Checking R ===${reset}\n"
install_or_die "R" \
  "command -v Rscript" \
  "brew install --cask r" \
  "e.g. 'sudo apt-get install r-base'" \
  "https://cran.r-project.org/"

printf "\n${bold}=== 3. Checking app artifacts ===${reset}\n"
missing=()
[[ -d python_env ]]                 || missing+=("python_env/")
[[ -d python/model ]]               || missing+=("python/model/")
[[ -d data/embeddings ]]            || missing+=("data/embeddings/")
[[ -f data/dd-abcd-6_0.parquet ]]   || missing+=("data/dd-abcd-6_0.parquet")

if (( ${#missing[@]} > 0 )); then
  warn "Missing: ${missing[*]}"
  if prompt_yn "Run ./setup.sh now to build them? (takes a few minutes)"; then
    ./setup.sh
  else
    die "Cannot run app without artifacts. Run ./setup.sh manually."
  fi
else
  ok "all present (python_env, python/model, data/embeddings, dd-abcd-6_0.parquet)"
fi

# Sanity: required source files.
for f in app.R .Rprofile python/backend.py; do
  [[ -f "$f" ]] || die "Required file missing: $f"
done

printf "\n${bold}=== 4. Launching Shiny app ===${reset}\n"
PORT=${PORT:-4444}
HOST=${HOST:-127.0.0.1}
ok "http://${HOST}:${PORT}  (Ctrl+C to stop)"
echo
exec Rscript -e "shiny::runApp(host = '${HOST}', port = ${PORT}, launch.browser = TRUE)"
