"""
One-shot build script — run locally whenever the source dictionary changes.

Produces every artifact the deployed app needs:
  python/model/model.onnx              (downloaded once from HF)
  python/model/tokenizer.json          (downloaded once from HF)
  data/embeddings/embeddings_<x>.npy   (fp16, per corpus)
  data/embeddings/metadata_<x>.npz     (metadata + text arrays, per corpus)

The dictionary parquet at data/<dictionary.parquet> is the single source of
truth. Both corpora are derived from it in-memory:
  imag   = every row with a non-null text_column value
  noimag = imag filtered to drop rows where metadata_column == "Imaging"

All paths, the embedding model, and the columns are read from config.yml at
the repo root — edit that file rather than hard-coding new values here.

pandas + huggingface_hub + pyyaml are only needed here (build-time), not in
the deployed runtime — that's why they're not in requirements.txt.

Usage:
    python python/build_embeddings.py
"""

import os
import shutil
import time
from pathlib import Path

import numpy as np
import pandas as pd
import yaml
from huggingface_hub import hf_hub_download

import onnxruntime as ort
from tokenizers import Tokenizer


ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / "config.yml"

with open(CONFIG_PATH) as f:
    CONFIG = yaml.safe_load(f)

REPO_ID       = CONFIG["model"]["repo_id"]
ONNX_HUB_PATH = CONFIG["model"]["onnx_hub_path"]
MAX_SEQ_LEN   = int(CONFIG["model"]["max_seq_len"])
BATCH_SIZE    = int(CONFIG["model"]["batch_size"])

TEXT_COL     = CONFIG["dictionary"]["text_column"]
METADATA_COL = CONFIG["dictionary"]["metadata_column"]
FULL_PARQUET = CONFIG["dictionary"]["parquet"]

MODEL_DIR = ROOT / "python" / "model"
DATA_DIR  = ROOT / "data"
EMB_DIR   = DATA_DIR / "embeddings"


def ensure_model_files():
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    targets = {
        "model.onnx":     ONNX_HUB_PATH,
        "tokenizer.json": "tokenizer.json",
    }
    for local_name, hub_path in targets.items():
        dest = MODEL_DIR / local_name
        if dest.exists():
            print(f"  [skip] {dest.relative_to(ROOT)} already exists "
                  f"({dest.stat().st_size/1e6:.1f} MB)")
            continue
        print(f"  downloading {hub_path} -> {dest.relative_to(ROOT)}")
        src = hf_hub_download(REPO_ID, hub_path)
        shutil.copy(src, dest)
        print(f"  saved {dest.stat().st_size/1e6:.1f} MB")


def build_encoder(max_len=MAX_SEQ_LEN):
    tok = Tokenizer.from_file(str(MODEL_DIR / "tokenizer.json"))
    tok.enable_padding(pad_id=0, pad_token="[PAD]")
    tok.enable_truncation(max_length=max_len)
    so = ort.SessionOptions()
    so.intra_op_num_threads = max(1, (os.cpu_count() or 2) // 2)
    sess = ort.InferenceSession(str(MODEL_DIR / "model.onnx"),
                                sess_options=so,
                                providers=["CPUExecutionProvider"])
    input_names = {i.name for i in sess.get_inputs()}
    return tok, sess, input_names


def encode(tok, sess, input_names, sentences, batch_size=BATCH_SIZE):
    out = []
    for i in range(0, len(sentences), batch_size):
        batch = sentences[i:i + batch_size]
        enc = tok.encode_batch(batch)
        ids  = np.array([e.ids            for e in enc], dtype=np.int64)
        mask = np.array([e.attention_mask for e in enc], dtype=np.int64)
        feeds = {"input_ids": ids, "attention_mask": mask}
        if "token_type_ids" in input_names:
            feeds["token_type_ids"] = np.zeros_like(ids)
        token_embeddings = sess.run(None, feeds)[0]
        m = mask[..., None].astype(np.float32)
        pooled = (token_embeddings * m).sum(1) / m.sum(1).clip(min=1e-9)
        norms = np.linalg.norm(pooled, axis=1, keepdims=True)
        norms[norms == 0] = 1.0
        out.append(pooled / norms)
    return np.vstack(out).astype(np.float32)


def encode_subset(df, suffix, tok, sess, input_names):
    texts = df[TEXT_COL].astype(str).tolist()
    metadata = df[METADATA_COL].astype(str).to_numpy()

    print(f"  [{suffix}] encoding {len(texts):,} {TEXT_COL}s")
    t0 = time.time()
    emb = encode(tok, sess, input_names, texts).astype(np.float16)
    dt = time.time() - t0

    emb_path  = EMB_DIR / f"embeddings_{suffix}.npy"
    meta_path = EMB_DIR / f"metadata_{suffix}.npz"
    np.save(emb_path, emb)
    # Keys are kept as `domains`/`labels` for backward compatibility with the
    # runtime loader in python/backend.py.
    np.savez_compressed(meta_path,
                        domains=metadata,
                        labels=np.array(texts, dtype=object))

    print(f"    encoded in {dt:.1f}s ({len(texts)/dt:.0f} sent/s)")
    print(f"    saved {emb_path.relative_to(ROOT)}  "
          f"({emb_path.stat().st_size/1e6:.1f} MB, fp16)")
    print(f"    saved {meta_path.relative_to(ROOT)} "
          f"({meta_path.stat().st_size/1e6:.2f} MB)")


def build_corpora(tok, sess, input_names):
    pq_path = DATA_DIR / FULL_PARQUET
    if not pq_path.exists():
        raise FileNotFoundError(
            f"{pq_path.relative_to(ROOT)} not found — drop the dictionary "
            f"parquet named in config.yml into data/ before running."
        )
    print(f"  reading {pq_path.relative_to(ROOT)} "
          f"({pq_path.stat().st_size/1e6:.1f} MB)")
    df = pd.read_parquet(pq_path, engine="fastparquet")
    for col in (TEXT_COL, METADATA_COL):
        if col not in df.columns:
            raise KeyError(
                f"column {col!r} missing from {FULL_PARQUET} — check "
                f"config.yml text_column/metadata_column."
            )

    imag = df.dropna(subset=[TEXT_COL]).reset_index(drop=True)
    noimag = imag[imag[METADATA_COL] != "Imaging"].reset_index(drop=True)
    print(f"  full={len(df):,}  imag={len(imag):,}  noimag={len(noimag):,}")

    encode_subset(noimag, "noimag", tok, sess, input_names)
    encode_subset(imag,   "imag",   tok, sess, input_names)


def write_manifest():
    """Record which parquet these embeddings were built against so the R UI
    can detect config.yml/embeddings drift and refuse to start (instead of
    silently displaying the wrong dictionary version)."""
    manifest = EMB_DIR / "manifest.txt"
    manifest.write_text(FULL_PARQUET + "\n")
    print(f"  wrote {manifest.relative_to(ROOT)} ({FULL_PARQUET})")


def main():
    print("=== 1. Model files ===")
    ensure_model_files()

    print("\n=== 2. Loading encoder ===")
    tok, sess, input_names = build_encoder()
    print(f"  inputs: {sorted(input_names)}")

    EMB_DIR.mkdir(parents=True, exist_ok=True)

    print("\n=== 3. Encoding corpora ===")
    build_corpora(tok, sess, input_names)

    print("\n=== 4. Manifest ===")
    write_manifest()

    print("\n=== Done ===")
    print(f"  Model dir:       {MODEL_DIR.relative_to(ROOT)}")
    print(f"  Embeddings dir:  {EMB_DIR.relative_to(ROOT)}")
    print(f"  Full dictionary: data/{FULL_PARQUET}")


if __name__ == "__main__":
    main()
