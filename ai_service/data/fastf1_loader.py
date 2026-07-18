"""FastF1 access — the only place this project reads Formula 1 data.

Serves two callers with one definition of "form", which is the point: the
rating a driver carries at training time and the rating sent at prediction time
must be computed the same way, or the model is scored on a feature it never saw.

- `build_training_frame` — past results, labelled, for training
- `race_entry_list` — the current entry list for one race, ready to predict on
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any, Dict, List, Optional

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


def form_from_mean_finish(mean_finish: float) -> float:
    """Map a mean finishing position onto the 0-100 rating the model expects.

    P1 -> 100, P20 -> 0, linear. A 22-car grid means the last two slots clip at
    0; that is deliberate, because the alternative — rescaling per season — would
    make a rating mean different things in training and at prediction time.
    """
    return float(min(100.0, max(0.0, 100.0 - (mean_finish - 1.0) * (100.0 / 19.0))))


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

    df["pace"] = rolling.map(form_from_mean_finish)
    return df


def season_schedule(season: int) -> List[Dict[str, Any]]:
    """The published calendar for a season."""
    import fastf1

    _enable_cache()
    schedule = fastf1.get_event_schedule(season, include_testing=False)

    return [
        {
            "round": int(event["RoundNumber"]),
            "name": str(event["EventName"]),
            "country": str(event["Country"]),
            "location": str(event["Location"]),
            "date": pd.Timestamp(event["EventDate"]).date().isoformat(),
        }
        for _, event in schedule.iterrows()
    ]


def _season_form(season: int, before_round: int) -> Dict[str, float]:
    """Each driver's form rating going into `before_round`, from real results.

    Uses the same mapping as training. Falls back to the previous season's tail
    early in the year, when this season has too few races to judge anyone on.
    """
    frames = []
    current = load_season_upto(season, before_round)
    if not current.empty:
        frames.append(current)

    if current.empty or current["round"].nunique() < FORM_WINDOW:
        previous = load_season(season - 1)
        if not previous.empty:
            frames.append(previous)

    if not frames:
        return {}

    df = pd.concat(frames, ignore_index=True).dropna(subset=["finish"])
    df = df.sort_values(["season", "round"])

    recent = df.groupby("code")["finish"].apply(lambda s: s.tail(FORM_WINDOW).mean())
    return {code: form_from_mean_finish(mean) for code, mean in recent.items()}


def load_season_upto(season: int, before_round: int) -> pd.DataFrame:
    """Completed race results for a season, excluding `before_round` onward."""
    df = load_season(season)
    if df.empty:
        return df
    return df[df["round"] < before_round]


def race_entry_list(season: int, rnd: int) -> Dict[str, Any]:
    """Entry list for one race: who is racing, from where, in what form.

    Grid comes from qualifying when it has run. Before that there is no grid, so
    the caller is told as much via `grid_source` rather than being handed a guess
    dressed up as a result.
    """
    import fastf1

    _enable_cache()

    event = fastf1.get_event(season, rnd)
    form = _season_form(season, rnd)

    grid: Dict[str, int] = {}
    grid_source = "none"
    entries: List[Dict[str, Any]] = []

    # Prefer the race itself (it has the real grid); fall back to qualifying.
    for session_name, source in (("R", "race"), ("Q", "qualifying")):
        try:
            session = fastf1.get_session(season, rnd, session_name)
            session.load(laps=False, telemetry=False, weather=False, messages=False)
        except Exception as exc:
            log.info("%s %s session %s unavailable: %s", season, rnd, session_name, exc)
            continue

        results = session.results
        if results is None or results.empty:
            continue

        for _, row in results.iterrows():
            code = str(row["Abbreviation"])
            entries.append(
                {
                    "code": code,
                    "name": str(row["FullName"]),
                    "number": _optional_int(row.get("DriverNumber")),
                    "team": str(row["TeamName"]),
                    "country": str(row.get("CountryCode") or "") or None,
                    "pace": form.get(code, 50.0),
                    # Only a completed race has a finishing order.
                    "finish": _optional_int(row.get("Position")) if source == "race" else None,
                    "status": str(row.get("Status") or "") or None,
                    "points": _optional_float(row.get("Points")),
                }
            )

            if source == "race":
                position = _optional_int(row.get("GridPosition"))
                if position:
                    grid[code] = position
            else:
                position = _optional_int(row.get("Position"))
                if position:
                    grid[code] = position

        grid_source = source if grid else "none"
        break

    # A future race has no session of its own, but the field is known from the
    # races already run — so predict on that rather than refusing outright.
    if not entries:
        entries = _entries_from_last_completed_round(season, rnd, form)

    if not entries:
        raise LookupError(f"no entry list published for {season} round {rnd}")

    # No grid yet: order by form so the field still has a defined running order,
    # and label it, because a form-ordered grid is an estimate, not a result.
    if not grid:
        grid_source = "form_estimate"
        ordered = sorted(entries, key=lambda e: -e["pace"])
        grid = {entry["code"]: i + 1 for i, entry in enumerate(ordered)}

    for entry in entries:
        entry["grid"] = grid.get(entry["code"])

    entries = [e for e in entries if e["grid"]]
    entries.sort(key=lambda e: e["grid"])

    return {
        "season": season,
        "round": rnd,
        "name": str(event["EventName"]),
        "country": str(event["Country"]),
        "location": str(event["Location"]),
        "date": pd.Timestamp(event["EventDate"]).date().isoformat(),
        "grid_source": grid_source,
        "entries": entries,
    }


def circuit_outline(season: int, rnd: int, samples: int = 240) -> Dict[str, Any]:
    """The track's shape, traced from a real fastest lap's position telemetry.

    Published circuit diagrams are copyrighted artwork, so the outline is
    derived from car position data instead: X/Y samples from the fastest lap,
    rotated by the circuit's own reference angle, normalised into a 0-100 box
    and returned as SVG path coordinates.

    Falls back to earlier seasons at the same event when the requested one has
    no telemetry yet.
    """
    import fastf1
    import numpy as np

    _enable_cache()

    event = fastf1.get_event(season, rnd)
    event_name = str(event["EventName"])
    location = str(event["Location"])

    for year in range(season, season - 4, -1):
        try:
            # An event name can move venue between seasons — the 2026 Spanish
            # Grand Prix is Madrid, the 2025 one was Barcelona. Falling back on
            # name alone would draw the wrong circuit, so require the location
            # to match before reusing an earlier season's telemetry.
            if year != season:
                past = fastf1.get_event(year, event_name)
                if str(past["Location"]) != location:
                    log.info(
                        "%s %s was at %s, not %s — skipping",
                        year, event_name, past["Location"], location,
                    )
                    continue

            session = fastf1.get_session(year, event_name, "R")
            # telemetry=False on purpose: the full telemetry load also parses
            # car data (speed, throttle), which raises for some sessions even
            # though position data is intact. Position is all a map needs.
            session.load(laps=True, telemetry=False, weather=False, messages=False)
            pos = _fastest_lap_positions(session)
        except Exception as exc:
            log.info("no telemetry for %s %s: %s", year, event_name, exc)
            continue

        if pos is None or pos.empty:
            continue

        x = pos["X"].to_numpy(dtype=float)
        y = pos["Y"].to_numpy(dtype=float)

        # FastF1 stores a per-circuit rotation so the map matches the
        # orientation the track is normally drawn in.
        try:
            angle = float(session.get_circuit_info().rotation) / 180 * np.pi
            x, y = (
                x * np.cos(angle) - y * np.sin(angle),
                x * np.sin(angle) + y * np.cos(angle),
            )
        except Exception:
            pass

        # Even sampling keeps the payload small without distorting the shape.
        if len(x) > samples:
            idx = np.linspace(0, len(x) - 1, samples).astype(int)
            x, y = x[idx], y[idx]

        span = max(x.max() - x.min(), y.max() - y.min()) or 1.0
        # SVG's Y axis points down; flip so the map isn't mirrored.
        nx = (x - x.min()) / span * 100
        ny = (y.max() - y) / span * 100

        return {
            "season": year,
            "round": rnd,
            "event": event_name,
            "width": round(float(nx.max()), 2),
            "height": round(float(ny.max()), 2),
            "points": [[round(float(a), 2), round(float(b), 2)] for a, b in zip(nx, ny)],
        }

    raise LookupError(f"no position telemetry available for {event_name}")


def _fastest_lap_positions(session) -> Optional[pd.DataFrame]:
    """X/Y samples covering exactly one lap — the shape of the circuit.

    Reads the position stream directly rather than through the telemetry API,
    which couples position to car data and fails when the latter is malformed.
    """
    from fastf1 import _api

    lap = session.laps.pick_fastest()
    if lap is None or pd.isna(lap["LapStartTime"]) or pd.isna(lap["LapTime"]):
        return None

    streams = _api.position_data(session.api_path)
    frame = streams.get(str(lap["DriverNumber"]))
    if frame is None or frame.empty:
        return None

    start = lap["LapStartTime"]
    end = start + lap["LapTime"]
    window = frame[(frame["Time"] >= start) & (frame["Time"] <= end)]

    # A car sitting in the pits reports (0, 0); those points would draw a
    # spike from the track to the origin.
    window = window[(window["X"] != 0) | (window["Y"] != 0)]
    if "Status" in window.columns:
        window = window[window["Status"] == "OnTrack"]

    return window if len(window) > 20 else None


def _entries_from_last_completed_round(
    season: int, before_round: int, form: Dict[str, float]
) -> List[Dict[str, Any]]:
    """Carry the most recent field forward to a race that hasn't run yet.

    Driver and team are taken from the last completed round, so a mid-season
    seat change is reflected. No grid is invented here — the caller labels the
    running order as a form estimate.
    """
    import fastf1

    for rnd in range(before_round - 1, 0, -1):
        try:
            session = fastf1.get_session(season, rnd, "R")
            session.load(laps=False, telemetry=False, weather=False, messages=False)
        except Exception:
            continue

        results = session.results
        if results is None or results.empty:
            continue

        return [
            {
                "code": str(row["Abbreviation"]),
                "name": str(row["FullName"]),
                "number": _optional_int(row.get("DriverNumber")),
                "team": str(row["TeamName"]),
                "country": str(row.get("CountryCode") or "") or None,
                "pace": form.get(str(row["Abbreviation"]), 50.0),
            }
            for _, row in results.iterrows()
        ]

    return []


def _optional_int(value: Any) -> Optional[int]:
    number = pd.to_numeric(value, errors="coerce")
    if pd.isna(number) or number <= 0:
        return None
    return int(number)


def _optional_float(value: Any) -> Optional[float]:
    number = pd.to_numeric(value, errors="coerce")
    return None if pd.isna(number) else float(number)


def build_training_frame(seasons: List[int]) -> pd.DataFrame:
    frames = [load_season(season) for season in seasons]
    df = pd.concat([f for f in frames if not f.empty], ignore_index=True)

    df = df.dropna(subset=["grid", "finish"])
    df = df[df["grid"] > 0]  # 0 means a pit lane start
    df = add_form_rating(df)

    df["won"] = (df["finish"] == 1).astype(int)
    df["podium"] = (df["finish"] <= 3).astype(int)
    return df
