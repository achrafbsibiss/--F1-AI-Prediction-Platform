from __future__ import annotations

import logging
import sys
from pathlib import Path

from fastapi import FastAPI, HTTPException

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.schemas import RacePredictionRequest, RacePredictionResponse  # noqa: E402
from models.race_model import ARTIFACT_PATH, DriverFeatures, RaceModel  # noqa: E402

log = logging.getLogger("ai_service")

app = FastAPI(title="F1 AI Prediction Service", version="0.1.0")

_model: RaceModel | None = None


def get_model() -> RaceModel:
    global _model
    if _model is None:
        if not ARTIFACT_PATH.exists():
            raise HTTPException(
                status_code=503,
                detail="model artifact missing; run python -m training.train_race_model",
            )
        _model = RaceModel.load()
        log.info("loaded model %s", _model.version)
    return _model


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "model_loaded": ARTIFACT_PATH.exists()}


@app.get("/data/season/{season}")
def season_calendar(season: int) -> dict:
    """The published calendar. Rails ingests this to create races."""
    from data.fastf1_loader import season_schedule

    try:
        return {"season": season, "races": season_schedule(season)}
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"FastF1 lookup failed: {exc}")


@app.get("/data/circuit/{season}/{rnd}/outline")
def circuit_map(season: int, rnd: int) -> dict:
    """Track outline traced from position telemetry (not a published diagram)."""
    from data.fastf1_loader import circuit_outline

    try:
        return circuit_outline(season, rnd)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"FastF1 lookup failed: {exc}")


@app.get("/data/race/{season}/{rnd}")
def race_entries(season: int, rnd: int) -> dict:
    """Entry list for one race — drivers, teams, grid slots and form ratings."""
    from data.fastf1_loader import race_entry_list

    try:
        return race_entry_list(season, rnd)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"FastF1 lookup failed: {exc}")


@app.post("/predict/race", response_model=RacePredictionResponse)
def predict_race(request: RacePredictionRequest) -> RacePredictionResponse:
    model = get_model()

    codes = [d.code for d in request.drivers]
    if len(set(codes)) != len(codes):
        raise HTTPException(status_code=422, detail="duplicate driver codes in request")

    features = [
        DriverFeatures(code=d.code, grid=d.grid, pace=d.pace) for d in request.drivers
    ]
    result = model.predict(features)
    win = result["win"]

    return RacePredictionResponse(
        race=request.race,
        model_version=model.version,
        winner=max(win, key=win.get),
        win_probabilities=win,
        podium_probabilities=result["podium"],
    )
