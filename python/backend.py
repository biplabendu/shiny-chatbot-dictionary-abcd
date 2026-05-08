import pandas as pd
import numpy as np
from sentence_transformers import SentenceTransformer
from pathlib import Path


SUPPORTED_MODELS = ["all-MiniLM-L6-v2", "all-MiniLM-L12-v2"]
DOMAINS_LIST = [
    'ABCD (General)', 'COVID-19', 'Endocannabinoid', 'Friends, Family, & Community',
    'Genetics', 'Hurricane Irma', 'Imaging', 'Linked External Data', 'MR Spectroscopy',
    'Mental Health', 'Neurocognition', 'Novel Technologies', 'Physical Health',
    'Social Development', 'Substance Use',
]

# Module-level cache: model and (df, embeddings) are loaded once and reused across searches.
_model_cache = {}
_data_cache = {}


def _get_model(model_name):
    if model_name not in _model_cache:
        _model_cache[model_name] = SentenceTransformer(f"sentence-transformers/{model_name}")
    return _model_cache[model_name]


def _get_data(data_path, use_imaging, model_name):
    key = (str(data_path), use_imaging, model_name)
    if key not in _data_cache:
        if use_imaging:
            csv_path = data_path / "dd-abcd-6_0_minimal.csv"
            embeddings_name = f"embeddings_{model_name}.npy"
        else:
            csv_path = data_path / "dd-abcd-6_0_minimal_noimag.csv"
            embeddings_name = f"embeddings_{model_name}_noimag.npy"

        df = pd.read_csv(csv_path).dropna(subset=["label"])

        embeddings_path = data_path / "local_embeddings"
        embeddings_file = embeddings_path / embeddings_name
        if not embeddings_file.exists():
            model = _get_model(model_name)
            sentences = df['label'].values.tolist()
            embeddings = model.encode(sentences, batch_size=64, normalize_embeddings=True, show_progress_bar=True)
            embeddings_path.mkdir(parents=True, exist_ok=True)
            np.save(embeddings_file, embeddings.astype("float32"))
        else:
            embeddings = np.load(embeddings_file)

        _data_cache[key] = (df, embeddings)

    return _data_cache[key]


def semantic_search(search_string, data_path, domains_list=None, model_name="all-MiniLM-L6-v2", cutoff=0.2):
    data_path = Path(data_path).resolve()
    if not data_path.exists():
        raise FileNotFoundError(f"Data path {data_path} does not exist")
    if model_name not in SUPPORTED_MODELS:
        raise ValueError(f"Model {model_name} not supported. Supported models: {SUPPORTED_MODELS}")

    if domains_list is None:
        domains_list = [d for d in DOMAINS_LIST if d != 'Imaging']

    use_imaging = 'Imaging' in domains_list
    model = _get_model(model_name)
    df, embeddings = _get_data(data_path, use_imaging, model_name)

    search_embedding = model.encode([search_string], normalize_embeddings=True, show_progress_bar=False)[0]

    return sentence_search(df, domains_list, embeddings, search_embedding, cutoff)


def sentence_search(df, domains_list, embeddings, search_embedding, cutoff=0.2):
    mask = df["domain"].isin(domains_list).values

    # Embeddings are L2-normalized, so dot product == cosine similarity.
    # This replaces the per-row scipy.cosine loop with a single matrix multiply.
    sims = np.zeros(len(df))
    sims[mask] = embeddings[mask] @ search_embedding

    sorted_index = np.argsort(sims)[::-1]
    sims_sorted = sims[sorted_index]
    keep = sims_sorted > cutoff
    return sims_sorted[keep], sorted_index[keep], np.array(df['label'].values)[sorted_index][keep]
