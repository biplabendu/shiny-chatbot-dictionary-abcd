import pandas as pd
import numpy as np
from sentence_transformers import SentenceTransformer, util
from scipy.spatial import distance as ssd
from pathlib import Path
import sys


SUPPORTED_MODELS = ["all-MiniLM-L6-v2", "all-MiniLM-L12-v2"]
DOMAINS_LIST = ['ABCD (General)','COVID-19','Endocannabinoid','Friends, Family, & Community','Genetics','Hurricane Irma','Imaging','Linked External Data','MR Spectroscopy','Mental Health','Neurocognition','Novel Technologies','Physical Health','Social Development','Substance Use']


def create_embeddings(df, model, batch_size=64):
    """
    Pre-computes embeddings for questions contained in a pre-loaded pandas DataFrame.

    The DataFrame is expected to have a 'label' column containing the text inputs
    for which embeddings will be generated using the provided model.
    """

    # Load Data and get the sentences
    sentences = df['label'].values.tolist()
            
    # Encode the sentences
    return model.encode(
        sentences,
        batch_size=batch_size,
        normalize_embeddings=True,
        show_progress_bar=True,
    )

def create_search_embeddings(search_string, model, batch_size=64):
    """
    Creates embeddings for the search string.
    """
    # Encode the sentences
    return model.encode(
        [search_string,],
        batch_size=batch_size,
        normalize_embeddings=True,
        show_progress_bar=True,
    )


def semantic_search(search_string, data_path, domains_list=None, model_name="all-MiniLM-L6-v2", cutoff=0.2):
    """
    Simulates: sentences_sorted[sims > cutoff]
    Calculates similarity for rows from the given domains, filters by cutoff, and sorts.
    """
    data_path = Path(data_path).resolve()
    print(f"Data path: {data_path}")
    if not data_path.exists():
        raise FileNotFoundError(f"Data path {data_path} does not exist")

    if model_name in SUPPORTED_MODELS:
        model = SentenceTransformer(f"sentence-transformers/{model_name}")
    else:
        raise ValueError(f"Model {model_name} not supported. Supported models: {SUPPORTED_MODELS}")

    # assuming that the default is csv without imaging questions
    if domains_list is None:
        domains_list = DOMAINS_LIST.copy()
        domains_list.remove('Imaging')
        
    # if the domains list doesn't contain Imaging, then use the csv without imaging questions
    if  'Imaging' not in domains_list:
        csv_path = data_path / "dd-abcd-6_0_minimal_noimag.csv"
        embeddings_name = f"embeddings_{model_name}_noimag.npy"
    else:
        csv_path = data_path / "dd-abcd-6_0_minimal.csv"
        embeddings_name = f"embeddings_{model_name}.npy"

    df = pd.read_csv(csv_path)
    df = df.dropna(subset=["label"])
    # creating embeddings for the questions if they don't exist
    embeddings_path = data_path / "local_embeddings"
    print(f"Checking if embeddings exist: {embeddings_path / embeddings_name}")
    if not (embeddings_path / embeddings_name).exists():
        embeddings = create_embeddings(df, model)
        if not embeddings_path.exists():
            print(f"Creating embeddings path: {embeddings_path}")
            embeddings_path.mkdir(parents=True, exist_ok=True)
        print(f"Saving embeddings to: {embeddings_path / embeddings_name}")
        np.save(embeddings_path / embeddings_name, embeddings.astype("float32"))
    else:
        embeddings = np.load(embeddings_path / embeddings_name)

    search_embeddings = create_search_embeddings(search_string, model)

    sims, sorted_index, sentences_sorted = sentence_search(df, domains_list, embeddings, search_embeddings, cutoff)

    return sims, sorted_index, sentences_sorted


def sentence_search(df, domains_list, embeddings, search_embedding, cutoff=0.2):
    # Compute cosine similarity scores for the search string and questions from the given domains

    sentences = df['label'].values.tolist()
    # get the sentences for the given domains
    mask = df["domain"].isin(domains_list)
    
    sims = np.zeros(len(df), dtype=float)    
    for i in np.where(mask)[0]:
        sims[i] = 1 - ssd.cosine(search_embedding[0], embeddings[i])

    # Sort sentences by similarity score in descending order (the most similar ones are first)
    sorted_index = np.argsort(sims)[::-1]
    sentences_sorted = np.array(sentences)[sorted_index]
    sims = sims[sorted_index]
    return sims[sims > cutoff], sorted_index[sims > cutoff], sentences_sorted[sims > cutoff]


# if __name__ == "__main__":
#     # when running from python the paths should work, otherwise you need to set the data path manually
#     DATA_PATH = Path(sys.argv[0]).resolve().parent.parent.parent.parent / "data"
#     # testing for relative path
#     #DATA_PATH_REL = "../data"
#     sims, sorted_index, sentences_sorted = semantic_search("variables to compute body mass index", data_path=DATA_PATH)
#     print(sentences_sorted[:10])
