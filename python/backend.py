"""
Runtime semantic search for the ABCD dictionary.

Encodes queries with MiniLM-L6-v2 quantized to ONNX int8 (no torch).
Loads pre-baked artifacts produced by python/build_embeddings.py:
  - embeddings_<x>.npy  (fp16 corpus embeddings)
  - metadata_<x>.npz    (domain + label arrays)

Runtime deps: numpy, onnxruntime, tokenizers. No pandas at runtime.
"""

import os
from pathlib import Path

import numpy as np
import onnxruntime as ort
from tokenizers import Tokenizer


DOMAINS_LIST = [
    'ABCD (General)', 'COVID-19', 'Endocannabinoid', 'Friends, Family, & Community',
    'Genetics', 'Hurricane Irma', 'Imaging', 'Linked External Data', 'MR Spectroscopy',
    'Mental Health', 'Neurocognition', 'Novel Technologies', 'Physical Health',
    'Social Development', 'Substance Use',
]

_MODEL_DIR = Path(__file__).resolve().parent / "model"
_MAX_LEN = 128

_encoder = None      # (tokenizer, session, input_names)
_data_cache = {}     # (data_path, use_imaging) -> (domains, labels, embeddings_fp32)


def _get_encoder():
    global _encoder
    if _encoder is None:
        tok = Tokenizer.from_file(str(_MODEL_DIR / "tokenizer.json"))
        tok.enable_padding(pad_id=0, pad_token="[PAD]")
        tok.enable_truncation(max_length=_MAX_LEN)
        so = ort.SessionOptions()
        so.intra_op_num_threads = max(1, (os.cpu_count() or 2) // 2)
        sess = ort.InferenceSession(str(_MODEL_DIR / "model.onnx"),
                                    sess_options=so,
                                    providers=["CPUExecutionProvider"])
        input_names = {i.name for i in sess.get_inputs()}
        _encoder = (tok, sess, input_names)
    return _encoder


def _encode(sentences):
    tok, sess, input_names = _get_encoder()
    enc = tok.encode_batch(list(sentences))
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
    return (pooled / norms).astype(np.float32)


def _get_data(data_path, use_imaging):
    key = (str(data_path), use_imaging)
    if key not in _data_cache:
        suffix = "imag" if use_imaging else "noimag"
        emb_path  = data_path / "embeddings" / f"embeddings_{suffix}.npy"
        meta_path = data_path / "embeddings" / f"metadata_{suffix}.npz"
        for p in (emb_path, meta_path):
            if not p.exists():
                raise FileNotFoundError(
                    f"Missing artifact: {p}. "
                    f"Run `python python/build_embeddings.py` to generate it."
                )
        embeddings = np.load(emb_path).astype(np.float32)
        meta = np.load(meta_path, allow_pickle=True)
        domains = meta["domains"]
        labels = meta["labels"]
        if not (len(embeddings) == len(domains) == len(labels)):
            raise ValueError(
                f"Artifact row mismatch for suffix={suffix}: "
                f"embeddings={len(embeddings)}, domains={len(domains)}, labels={len(labels)}. "
                f"Rebuild with python/build_embeddings.py."
            )
        _data_cache[key] = (domains, labels, embeddings)

    return _data_cache[key]


def semantic_search(search_string, data_path, domains_list=None, cutoff=0.2, **_):
    """Return (similarities, indices, labels) — same shape the R app expects.

    Indices are relative to the (filtered-by-imaging) corpus, matching the
    original API. `**_` accepts and ignores legacy kwargs (e.g. model_name).
    """
    data_path = Path(data_path).resolve()
    if not data_path.exists():
        raise FileNotFoundError(f"Data path {data_path} does not exist")

    if domains_list is None:
        domains_list = [d for d in DOMAINS_LIST if d != 'Imaging']

    use_imaging = 'Imaging' in domains_list
    domains, labels, embeddings = _get_data(data_path, use_imaging)

    search_embedding = _encode([search_string])[0]

    mask = np.isin(domains, list(domains_list))
    sims = np.zeros(len(domains), dtype=np.float32)
    sims[mask] = embeddings[mask] @ search_embedding

    sorted_index = np.argsort(sims)[::-1]
    sims_sorted = sims[sorted_index]
    keep = sims_sorted > cutoff
    return (sims_sorted[keep],
            sorted_index[keep],
            labels[sorted_index][keep])
