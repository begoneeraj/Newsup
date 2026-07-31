"""Fake news content classifier trained on the ISOT Fake News Dataset.

Dataset (not included in this repo — download manually from Kaggle:
https://www.kaggle.com/datasets/clmentbisaillon/fake-and-real-news-dataset
and place True.csv / Fake.csv under data/isot/):
  - True.csv: title, text, subject, date  (real news, label 0)
  - Fake.csv: title, text, subject, date  (fake news, label 1)

Usage:
    python -m src.ml.fake_news_classifier          # train + evaluate + export
    from src.ml.fake_news_classifier import predict_fake_probability
    predict_fake_probability("Some headline", "Some body text")

The exported pkl is a single sklearn Pipeline (TF-IDF + engineered features
+ LogisticRegression) so training and inference share identical
preprocessing — there's no separate vectorizer/scaler file to keep in sync.
"""

from __future__ import annotations

import re
import string
from pathlib import Path

import joblib
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import classification_report, confusion_matrix
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

_DIR = Path(__file__).resolve().parent
DATA_DIR = _DIR.parent.parent / "data" / "isot"
MODEL_PATH = _DIR / "fake_news_classifier.pkl"

# Supplementary sources, merged in on top of ISOT if present (both optional —
# training falls back to ISOT-only if these files aren't there). Diversifies
# the REAL/FAKE examples beyond ISOT's single-scraper-per-class collection,
# which otherwise lets the model key off "is this Reuters-formatted" rather
# than truthfulness. Two Kaggle datasets considered but deliberately EXCLUDED:
#   - khushikyad001/fake-news-detection: synthetic placeholder data (titles
#     are literally "Breaking News 1".."Breaking News 4000", every body is
#     the same templated sentence, 5 unique authors across 4000 rows) — no
#     real signal to learn from, only noise.
#   - mrisdal's rows here are used (see _load_mrisdal_fake), but only ever as
#     FAKE examples — it has no REAL counterpart of its own.
TEXTDB3_PATH = DATA_DIR.parent / "textdb3" / "fake_or_real_news.csv"
MRISDAL_PATH = DATA_DIR.parent / "mrisdal" / "fake.csv"

ENGINEERED_COLUMNS = ["caps_ratio", "exclamation_count", "has_source_citation", "word_count"]
_SOURCE_CITATION_PHRASES = ("according to", "said", "reported")


# ---------------------------------------------------------------------------
# Preprocessing / feature engineering
# ---------------------------------------------------------------------------
# Engineered features (caps_ratio, exclamation_count) need the ORIGINAL casing
# and punctuation, so they're computed from raw_content before clean_text()
# strips exactly that information for the TF-IDF input column.

def clean_text(text: str) -> str:
    """Lowercase and strip punctuation, for the TF-IDF input column."""
    text = text.lower()
    text = text.translate(str.maketrans("", "", string.punctuation))
    return re.sub(r"\s+", " ", text).strip()


def _caps_ratio(text: str) -> float:
    return sum(1 for c in text if c.isupper()) / len(text) if text else 0.0


def _has_source_citation(text: str) -> int:
    lowered = text.lower()
    return int(any(phrase in lowered for phrase in _SOURCE_CITATION_PHRASES))


def add_engineered_features(df: pd.DataFrame, content_col: str = "raw_content") -> pd.DataFrame:
    """Adds caps_ratio, exclamation_count, has_source_citation, word_count,
    plus clean_content (the cleaned TF-IDF input), from `content_col`."""
    df = df.copy()
    df["caps_ratio"] = df[content_col].apply(_caps_ratio)
    df["exclamation_count"] = df[content_col].apply(lambda t: t.count("!"))
    df["has_source_citation"] = df[content_col].apply(_has_source_citation)
    df["word_count"] = df[content_col].apply(lambda t: len(t.split()))
    df["clean_content"] = df[content_col].apply(clean_text)
    return df


# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------

def _load_textdb3(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path)[["title", "text", "label"]].copy()
    df["label"] = df["label"].map({"REAL": 0, "FAKE": 1})
    return df


def _load_mrisdal_fake(path: Path) -> pd.DataFrame:
    # latin-1 — same Windows-1252 issue as the ISOT CSVs.
    df = pd.read_csv(path, encoding="latin-1")[["title", "text"]].copy()
    df["label"] = 1  # this dataset is fake-articles-only; see module docstring
    return df


def load_dataset(data_dir: Path = DATA_DIR, use_supplementary: bool = True) -> pd.DataFrame:
    # latin-1, not utf-8 — the ISOT CSVs contain Windows-1252 curly
    # quotes/dashes that aren't valid UTF-8 and otherwise raise
    # UnicodeDecodeError partway through the file.
    true_df = pd.read_csv(data_dir / "True.csv", encoding="latin-1")[["title", "text"]].copy()
    true_df["label"] = 0
    fake_df = pd.read_csv(data_dir / "Fake.csv", encoding="latin-1")[["title", "text"]].copy()
    fake_df["label"] = 1

    frames = [true_df, fake_df]
    if use_supplementary:
        if TEXTDB3_PATH.exists():
            frames.append(_load_textdb3(TEXTDB3_PATH))
        if MRISDAL_PATH.exists():
            frames.append(_load_mrisdal_fake(MRISDAL_PATH))

    df = pd.concat(frames, ignore_index=True)
    df["title"] = df["title"].fillna("")
    df["text"] = df["text"].fillna("")
    df["raw_content"] = (df["title"] + " " + df["text"]).str.strip()

    # Drop rows with no actual content (mrisdal has some empty title/text
    # rows) and exact duplicates that can appear across sources collected in
    # overlapping time windows — both would otherwise leak between train/test.
    df = df[df["raw_content"] != ""]
    df = df.drop_duplicates(subset=["title", "text"]).reset_index(drop=True)

    return add_engineered_features(df)


# ---------------------------------------------------------------------------
# Model
# ---------------------------------------------------------------------------

def build_pipeline() -> Pipeline:
    preprocessor = ColumnTransformer(
        transformers=[
            ("tfidf", TfidfVectorizer(max_features=10_000, ngram_range=(1, 2), stop_words="english"), "clean_content"),
            ("engineered", StandardScaler(), ENGINEERED_COLUMNS),
        ]
    )
    return Pipeline(
        steps=[
            ("features", preprocessor),
            # class_weight="balanced" — merging in mrisdal's fake-only rows
            # skews the combined dataset toward the FAKE class (~62/38 with
            # all supplementary sources included), and would otherwise bias
            # the model toward predicting FAKE by default.
            ("clf", LogisticRegression(max_iter=1000, class_weight="balanced")),
        ]
    )


def train(data_dir: Path = DATA_DIR, model_path: Path = MODEL_PATH) -> Pipeline:
    df = load_dataset(data_dir)
    X = df[["clean_content", *ENGINEERED_COLUMNS]]
    y = df["label"]

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    pipeline = build_pipeline()
    pipeline.fit(X_train, y_train)

    y_pred = pipeline.predict(X_test)
    print("Classification report:")
    print(classification_report(y_test, y_pred, target_names=["REAL", "FAKE"]))
    print("Confusion matrix (rows=actual, cols=predicted, order=[REAL, FAKE]):")
    print(confusion_matrix(y_test, y_pred))

    joblib.dump(pipeline, model_path)
    print(f"Model exported to {model_path}")

    return pipeline


# ---------------------------------------------------------------------------
# Inference
# ---------------------------------------------------------------------------

def predict_fake_probability(headline: str, body: str = "", model_path: Path = MODEL_PATH) -> float:
    """Returns the probability (0.0-1.0) that `headline` + `body` is fake."""
    pipeline: Pipeline = joblib.load(model_path)

    raw_content = f"{headline} {body}".strip()
    row = pd.DataFrame([{"raw_content": raw_content}])
    row = add_engineered_features(row)

    fake_class_idx = list(pipeline.classes_).index(1)
    probability = pipeline.predict_proba(row[["clean_content", *ENGINEERED_COLUMNS]])[0][fake_class_idx]
    return float(probability)


if __name__ == "__main__":
    train()
