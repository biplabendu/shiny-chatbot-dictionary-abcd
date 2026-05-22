# ── Stage 1: Python venv ─────────────────────────────────────────────────────
# Uses ubuntu:24.04 to match the rocker/r-ver:4.5.2 base OS, keeping the venv
# Python binary and shared libs compatible across stages.
FROM ubuntu:24.04 AS python-builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3.12 python3.12-venv \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY requirements.txt .
RUN python3.12 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

# ── Stage 2: R + Python runtime ──────────────────────────────────────────────
# rocker/r-ver:4.5.2 ships exactly R 4.5.2 on Ubuntu 24.04 (noble), matching
# what renv.lock was written against. This avoids the R 4.6.0 API breakage
# when using the CRAN apt repo directly.
FROM rocker/r-ver:4.5.2

ENV DEBIAN_FRONTEND=noninteractive \
    VIRTUAL_ENV=/opt/venv \
    PATH="/opt/venv/bin:$PATH" \
    RETICULATE_PYTHON=/opt/venv/bin/python

# System libraries required by R packages (cairo, curl, xml, etc.)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3.12 libpython3.12 \
        pandoc \
        libcurl4-openssl-dev libssl-dev libxml2-dev \
        libfontconfig1-dev libharfbuzz-dev libfribidi-dev \
        libfreetype6-dev libpng-dev libtiff5-dev libjpeg-dev \
        libcairo2-dev libwebp-dev libxt-dev libxrender1 \
        libglpk-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=python-builder /opt/venv /opt/venv

# Copy renv infrastructure before restoring packages (cache-friendly layer order).
# --vanilla skips .Rprofile so renv's bootstrap sequence can't shadow base functions.
# PPM binary URL for Ubuntu 24.04 (noble) avoids compiling packages from source.
COPY renv.lock .Rprofile ./
COPY renv/ renv/
# --vanilla on the first call only: prevents renv/activate.R from shadowing
# install.packages before renv is installed.
# The second call runs normally so .Rprofile activates the project library
# at renv/library/, and restore() installs packages there.
RUN Rscript --vanilla -e "install.packages('renv', repos='https://packagemanager.posit.co/cran/__linux__/noble/latest')" \
    && Rscript -e "renv::restore(prompt=FALSE, repos=c(PPM='https://packagemanager.posit.co/cran/__linux__/noble/latest'))"

# Copy app source and pre-built artifacts
COPY app.R requirements.txt ./
COPY python/ python/
COPY www/ www/
COPY data/ data/

EXPOSE 8000
CMD ["R", "-e", "shiny::runApp('/app', host='0.0.0.0', port=8000)"]
