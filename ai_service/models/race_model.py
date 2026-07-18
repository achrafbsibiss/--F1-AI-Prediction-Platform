"""Race outcome model: per-driver win / podium probabilities.

Two independent binary classifiers score each driver, then the scores are
normalised across the field so win probabilities sum to 1 and podium
probabilities sum to 3 (three podium slots).
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Sequence

import joblib
import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

MODEL_VERSION = "race-v1"
ARTIFACT_PATH = Path(__file__).resolve().parent / "artifacts" / "race_model.joblib"

FEATURE_NAMES = ["grid", "pace", "grid_rank_pct", "pace_gap_to_best", "front_row"]


@dataclass
class DriverFeatures:
    code: str
    grid: int
    pace: float


def build_features(drivers: Sequence[DriverFeatures]) -> np.ndarray:
    """Features are relative to the rest of the field, not absolute."""
    field_size = len(drivers)
    best_pace = max(d.pace for d in drivers)

    rows = []
    for d in drivers:
        rows.append(
            [
                d.grid,
                d.pace,
                (d.grid - 1) / max(field_size - 1, 1),
                best_pace - d.pace,
                1.0 if d.grid <= 2 else 0.0,
            ]
        )
    return np.asarray(rows, dtype=float)


def _new_pipeline() -> Pipeline:
    # Logistic regression rather than a tree ensemble: a season yields only ~24
    # winners, and trees produce a non-monotonic tail (a P13 car outranking a
    # P5 car) on that little signal. A linear model stays ordered in grid/pace.
    return Pipeline(
        [
            ("scale", StandardScaler()),
            ("clf", LogisticRegression(C=1.0, max_iter=1000, random_state=42)),
        ]
    )


class RaceModel:
    def __init__(self, win_clf: Pipeline, podium_clf: Pipeline, version: str = MODEL_VERSION):
        self.win_clf = win_clf
        self.podium_clf = podium_clf
        self.version = version

    @classmethod
    def train(cls, X: np.ndarray, y_win: np.ndarray, y_podium: np.ndarray) -> "RaceModel":
        win_clf = _new_pipeline().fit(X, y_win)
        podium_clf = _new_pipeline().fit(X, y_podium)
        return cls(win_clf, podium_clf)

    def save(self, path: Path = ARTIFACT_PATH) -> Path:
        path.parent.mkdir(parents=True, exist_ok=True)
        joblib.dump(
            {"win": self.win_clf, "podium": self.podium_clf, "version": self.version}, path
        )
        return path

    @classmethod
    def load(cls, path: Path = ARTIFACT_PATH) -> "RaceModel":
        bundle = joblib.load(path)
        return cls(bundle["win"], bundle["podium"], bundle.get("version", MODEL_VERSION))

    def predict(self, drivers: List[DriverFeatures]) -> Dict[str, Dict[str, float]]:
        X = build_features(drivers)
        win_scores = self.win_clf.predict_proba(X)[:, 1]
        podium_scores = self.podium_clf.predict_proba(X)[:, 1]

        codes = [d.code for d in drivers]
        return {
            "win": _normalise(codes, win_scores, total=1.0),
            "podium": _normalise(codes, podium_scores, total=3.0, cap=1.0),
        }


def _normalise(
    codes: Sequence[str], scores: np.ndarray, total: float, cap: float | None = None
) -> Dict[str, float]:
    scores = np.clip(scores, 1e-6, None)
    probs = scores / scores.sum() * total

    if cap is not None:
        # Redistribute whatever spills over the cap onto the uncapped drivers.
        for _ in range(10):
            overflow = np.clip(probs - cap, 0, None).sum()
            if overflow <= 1e-9:
                break
            probs = np.minimum(probs, cap)
            headroom = cap - probs
            if headroom.sum() <= 1e-9:
                break
            probs = probs + overflow * headroom / headroom.sum()

    return {code: round(float(p), 5) for code, p in zip(codes, probs)}
