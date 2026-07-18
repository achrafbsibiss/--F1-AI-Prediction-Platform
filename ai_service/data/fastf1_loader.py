"""Build a training frame of past race results using FastF1.

One row per driver per race: starting grid slot, a form rating derived from the
driver's recent results, and whether they won / finished on the podium.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import List

import pandas as pd

CACHE_DIR = Path(__file__).resolve().parent / "fastf1_cache"
FORM_WINDOW = 5  # races used for the rolling form rating

log = logging.getLogger(__name__)


def _enable_cache() -> None:
    import fastf1

    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    fastf1.Cache.enable_cache(str(CACHE_DIR))


def load_season(season: int) -> pd.DataFrame:
    """Race results for one season, ordered by round."""
    import fastf1

    _enable_cache()
    schedule = fastf1.get_event_schedule(season, include_testing=False)

    frames: List[pd.DataFrame] = []
    for _, event in schedule.iterrows():
        try:
            session = fastf1.get_session(season, int(event["RoundNumber"]), "R")
            session.load(laps=False, telemetry=False, weather=False, messages=False)
        except Exception as exc:  # a session may not have happened yet
            log.warning("skipping %s %s: %s", season, event["EventName"], exc)
            continue

        results = session.results
        if results is None or results.empty:
            continue

        frames.append(
            pd.DataFrame(
                {
                    "season": season,
                    "round": int(event["RoundNumber"]),
                    "code": results["Abbreviation"].astype(str),
                    "grid": pd.to_numeric(results["GridPosition"], errors="coerce"),
                    "finish": pd.to_numeric(results["Position"], errors="coerce"),
                }
            )
        )

    if not frames:
        return pd.DataFrame(columns=["season", "round", "code", "grid", "finish"])

    return pd.concat(frames, ignore_index=True)


def add_form_rating(df: pd.DataFrame) -> pd.DataFrame:
    """0-100 rating from each driver's mean finish over the previous races.

    Shifted by one race so a row never sees its own result.
    """
    df = df.sort_values(["season", "round"]).copy()

    rolling = (
        df.groupby("code")["finish"]
        .transform(lambda s: s.shift(1).rolling(FORM_WINDOW, min_periods=1).mean())
    )
    # Mid-grid (P10) is the fallback for a driver with no history yet.
    rolling = rolling.fillna(10.0)

    df["pace"] = (100.0 - (rolling - 1.0) * (100.0 / 19.0)).clip(0, 100)
    return df


def build_training_frame(seasons: List[int]) -> pd.DataFrame:
    frames = [load_season(season) for season in seasons]
    df = pd.concat([f for f in frames if not f.empty], ignore_index=True)

    df = df.dropna(subset=["grid", "finish"])
    df = df[df["grid"] > 0]  # 0 means a pit lane start
    df = add_form_rating(df)

    df["won"] = (df["finish"] == 1).astype(int)
    df["podium"] = (df["finish"] <= 3).astype(int)
    return df
