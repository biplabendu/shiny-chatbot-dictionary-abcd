"""
One-shot build script — run locally whenever the source CSVs change.

Produces every artifact the deployed app needs:
  python/model/model.onnx          (downloaded once from HF)
  python/model/tokenizer.json      (downloaded once from HF)
  data/embeddings/embeddings_<x>.npy  (fp16, per imag/noimag corpus)
  data/embeddings/metadata_<x>.npz    (domain + label arrays, per corpus)
  data/dd-abcd-6_0.parquet         (full dictionary for the R UI)

pandas + huggingface_hub are only needed here (build-time), not in the
deployed runtime — that's why they're not in requirements.txt.

Usage:
    python python/build_embeddings.py
"""

import os
import shutil
import time
from pathlib import Path

import numpy as np
import pandas as pd
from huggingface_hub import hf_hub_download

import onnxruntime as ort
from tokenizers import Tokenizer


REPO_ID = "sentence-transformers/all-MiniLM-L6-v2"
ONNX_HUB_PATH = "onnx/model_quint8_avx2.onnx"   # AVX2 is universal on Linux x86_64.

ROOT = Path(__file__).resolve().parent.parent
MODEL_DIR = ROOT / "python" / "model"
DATA_DIR = ROOT / "data"
EMB_DIR = DATA_DIR / "embeddings"

# (csv_filename, suffix used in output filenames)
CORPORA = [
    ("dd-abcd-6_0_minimal_noimag.csv", "noimag"),
    ("dd-abcd-6_0_minimal.csv",        "imag"),
]

# Full dictionary CSV that the R UI displays (converted once to parquet).
FULL_CSV = "dd-abcd-6_0.csv"
FULL_PARQUET = "dd-abcd-6_0.parquet"


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


def build_encoder(max_len=128):
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


def encode(tok, sess, input_names, sentences, batch_size=64):
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


def build_corpus(csv_name, suffix, tok, sess, input_names):
    csv_path = DATA_DIR / csv_name
    if not csv_path.exists():
        print(f"  [skip] {csv_name} not found")
        return
    df = pd.read_csv(csv_path).dropna(subset=["label"]).reset_index(drop=True)
    labels = df["label"].astype(str).tolist()
    domains = df["domain"].astype(str).to_numpy()

    print(f"  {csv_name}: encoding {len(labels):,} labels")
    t0 = time.time()
    emb = encode(tok, sess, input_names, labels).astype(np.float16)
    dt = time.time() - t0

    emb_path  = EMB_DIR / f"embeddings_{suffix}.npy"
    meta_path = EMB_DIR / f"metadata_{suffix}.npz"
    np.save(emb_path, emb)
    np.savez_compressed(meta_path,
                        domains=domains,
                        labels=np.array(labels, dtype=object))

    print(f"    encoded in {dt:.1f}s ({len(labels)/dt:.0f} sent/s)")
    print(f"    saved {emb_path.relative_to(ROOT)}  "
          f"({emb_path.stat().st_size/1e6:.1f} MB, fp16)")
    print(f"    saved {meta_path.relative_to(ROOT)} "
          f"({meta_path.stat().st_size/1e6:.2f} MB)")


def build_full_parquet():
    """Convert the big UI dictionary CSV to parquet using fastparquet
    so we don't drag pyarrow into the dev install."""
    csv_path = DATA_DIR / FULL_CSV
    pq_path  = DATA_DIR / FULL_PARQUET
    if not csv_path.exists():
        print(f"  [skip] {FULL_CSV} not found")
        return
    if pq_path.exists() and pq_path.stat().st_mtime > csv_path.stat().st_mtime:
        print(f"  [skip] {FULL_PARQUET} is up to date "
              f"({pq_path.stat().st_size/1e6:.1f} MB)")
        return
    print(f"  reading {FULL_CSV} ({csv_path.stat().st_size/1e6:.1f} MB)")
    df = pd.read_csv(csv_path, dtype=str, keep_default_na=False)
    print(f"  writing {FULL_PARQUET} (snappy)")
    df.to_parquet(pq_path, engine="fastparquet", compression="snappy", index=False)
    print(f"    saved {pq_path.relative_to(ROOT)} "
          f"({pq_path.stat().st_size/1e6:.1f} MB)")


def main():
    print("=== 1. Model files ===")
    ensure_model_files()

    print("\n=== 2. Loading encoder ===")
    tok, sess, input_names = build_encoder()
    print(f"  inputs: {sorted(input_names)}")

    EMB_DIR.mkdir(parents=True, exist_ok=True)

    print("\n=== 3. Encoding corpora ===")
    for csv_name, suffix in CORPORA:
        build_corpus(csv_name, suffix, tok, sess, input_names)

    print("\n=== 4. Full dictionary -> parquet (for R UI) ===")
    build_full_parquet()

    print("\n=== Done ===")
    print(f"  Model dir:       {MODEL_DIR.relative_to(ROOT)}")
    print(f"  Embeddings dir:  {EMB_DIR.relative_to(ROOT)}")
    print(f"  Full dictionary: data/{FULL_PARQUET}")


if __name__ == "__main__":
    main()
