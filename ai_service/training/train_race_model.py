"""Train the race outcome model.

    python -m training.train_race_model --seasons 2022 2023 2024 2025 2026

Pulls real results through FastF1. With --synthetic (or when FastF1 is
unreachable) it falls back to a generated dataset so the service can boot
offline — that fallback model is a placeholder, not a calibrated predictor.
"""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from models.race_model import DriverFeatures, RaceModel, build_features  # noqa: E402

log = logging.getLogger("train")

FIELD_SIZE = 20


def synthetic_frame(n_races: int = 800, seed: int = 42) -> pd.DataFrame:
    """Simulate races where finishing order is grid + form + noise.

    Roughly reproduces the observed pole-to-win rate of modern F1 (~40%).
    """
    rng = np.random.default_rng(seed)
    rows = []

    for race in range(n_races):
        pace = np.sort(rng.normal(80, 9, FIELD_SIZE))[::-1].clip(40, 100)
        # Qualifying: pace plus noise decides the grid.
        grid_order = np.argsort(-(pace + rng.normal(0, 4, FIELD_SIZE)))
        grid = np.empty(FIELD_SIZE, dtype=int)
        grid[grid_order] = np.arange(1, FIELD_SIZE + 1)

        # Race: track position matters, but pace and luck can override it.
        race_score = -grid * 1.6 + (pace - pace.mean()) * 0.5 + rng.normal(0, 3.2, FIELD_SIZE)
        dnf = rng.random(FIELD_SIZE) < 0.07
        race_score[dnf] -= 100

        finish = np.empty(FIELD_SIZE, dtype=int)
        finish[np.argsort(-race_score)] = np.arange(1, FIELD_SIZE + 1)

        for i in range(FIELD_SIZE):
            rows.append(
                {
                    "race": race,
                    "code": f"D{i:02d}",
                    "grid": int(grid[i]),
                    "pace": float(pace[i]),
                    "finish": int(finish[i]),
                }
            )

    df = pd.DataFrame(rows)
    df["won"] = (df["finish"] == 1).astype(int)
    df["podium"] = (df["finish"] <= 3).astype(int)
    return df


def frame_to_matrix(df: pd.DataFrame, group_key: list[str]) -> np.ndarray:
    """Features are field-relative, so build them one race at a time."""
    blocks = []
    for _, race_df in df.groupby(group_key, sort=False):
        drivers = [
            DriverFeatures(code=r.code, grid=int(r.grid), pace=float(r.pace))
            for r in race_df.itertuples()
        ]
        blocks.append(build_features(drivers))
    return np.vstack(blocks)


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--seasons", type=int, nargs="+", default=[2022, 2023, 2024, 2025, 2026]
    )
    parser.add_argument("--synthetic", action="store_true", help="skip FastF1 entirely")
    args = parser.parse_args()

    df = None
    group_key = ["season", "round"]

    if not args.synthetic:
        try:
            from data.fastf1_loader import build_training_frame

            log.info("loading seasons %s via FastF1 (first run downloads data)", args.seasons)
            df = build_training_frame(args.seasons)
        except Exception as exc:
            log.warning("FastF1 load failed (%s); falling back to synthetic data", exc)

    if df is None or df.empty:
        log.warning("training on SYNTHETIC data — placeholder model, not calibrated on real races")
        df = synthetic_frame()
        group_key = ["race"]

    # Keep races ordered so field-relative features line up with the labels.
    df = df.sort_values(group_key).reset_index(drop=True)

    X = frame_to_matrix(df, group_key)
    y_win = df["won"].to_numpy()
    y_podium = df["podium"].to_numpy()

    log.info("training on %d rows across %d races", len(df), df.groupby(group_key).ngroups)
    model = RaceModel.train(X, y_win, y_podium)
    path = model.save()
    log.info("saved %s", path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
