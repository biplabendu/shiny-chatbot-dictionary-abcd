# Obtaining the data dictionary

The build pipeline (`python/build_embeddings.py`, run by `setup.sh`) reads a
single parquet file as its source of truth. The filename is set in `config.yml`
under `dictionary.parquet` (e.g. `dd-abcd-7_0.parquet`); the build script
derives both corpora from it in-memory:

- `imag`   — every row with a non-null `label`
- `noimag` — `imag` filtered to drop rows where `domain == "Imaging"`

The parquet must contain at least the columns named in `config.yml` as
`text_column` (default `label`) and `metadata_column` (default `domain`).

### 1. Download the ABCD dictionary in R

```r
dd <- NBDCtools::get_dd_abcd(release = "7.0")
```

### 2. Save it as parquet at the path config.yml expects

```r
nanoparquet::write_parquet(dd, "data/dd-abcd-7_0.parquet")
```

(Use `arrow::write_parquet()` if you prefer; the file just needs to be readable
by `pandas.read_parquet(engine="fastparquet")`.)

### 3. (Optional) point config.yml at a different release

Edit `config.yml`:

```yaml
dictionary:
  parquet: dd-abcd-7_0.parquet   # change this when a new release lands
  text_column: label
  metadata_column: domain
```

### 4. Rebuild embeddings

```sh
./setup.sh
```

This regenerates `data/embeddings/{embeddings,metadata}_{imag,noimag}.*` and
writes `data/embeddings/manifest.txt` recording which parquet the embeddings
were built against — the R UI checks this at startup and refuses to start if it
drifts from `config.yml`.
