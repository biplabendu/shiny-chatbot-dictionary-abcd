FROM pytorch/pytorch:2.2.2-cuda12.1-cudnn8-runtime AS python-builder

ENV DEBIAN_FRONTEND=noninteractive

ARG APP_DIR=dev/app-v1

WORKDIR /app/app-v1

COPY ${APP_DIR}/requirements.txt /app/app-v1/
RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt


FROM pytorch/pytorch:2.2.2-cuda12.1-cudnn8-runtime AS final

ENV DEBIAN_FRONTEND=noninteractive \
    VIRTUAL_ENV=/opt/venv \
    PATH="/opt/venv/bin:$PATH" \
    RETICULATE_PYTHON=/opt/venv/bin/python \
    RENV_PATHS_CACHE=/renv/cache

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        software-properties-common \
    && curl -fsSL https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc \
        | gpg --dearmor -o /usr/share/keyrings/cran.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cran.gpg] https://cloud.r-project.org/bin/linux/ubuntu jammy-cran40/" \
        > /etc/apt/sources.list.d/cran.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        r-base \
        r-base-dev \
        pandoc \
        libcurl4-openssl-dev \
        libssl-dev \
        libxml2-dev \
        libfontconfig1-dev \
        libharfbuzz-dev \
        libfribidi-dev \
        libfreetype6-dev \
        libpng-dev \
        libtiff5-dev \
        libjpeg-dev \
        libcairo2-dev \
        libwebp-dev \
        libxt-dev \
        libxrender1 \
        libglpk-dev \
    && rm -rf /var/lib/apt/lists/*

ARG APP_DIR=dev/app-v1

WORKDIR /app/app-v1

COPY --from=python-builder /opt/venv /opt/venv

COPY ${APP_DIR}/ /app/app-v1
RUN R -e "install.packages('renv', repos='https://cloud.r-project.org')" \
    && R -e "renv::restore(prompt = FALSE)"
COPY data/ /app/data/
RUN rm -rf /app/app-v1/data && ln -s /app/data /app/app-v1/data

EXPOSE 8000
CMD ["R", "-e", "shiny::runApp('/app/app-v1', host='0.0.0.0', port=8000)"]
