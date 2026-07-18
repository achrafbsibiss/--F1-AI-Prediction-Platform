from typing import Dict, List, Optional

from pydantic import BaseModel, Field


class DriverInput(BaseModel):
    code: str
    name: str
    grid: int = Field(ge=1, le=24)
    pace: float = Field(ge=0, le=100, description="0-100 form rating")
    team: Optional[str] = None


class RacePredictionRequest(BaseModel):
    race: str
    season: Optional[int] = None
    laps: Optional[int] = None
    drivers: List[DriverInput] = Field(min_length=2)


class RacePredictionResponse(BaseModel):
    race: str
    model_version: str
    winner: str
    win_probabilities: Dict[str, float]
    podium_probabilities: Dict[str, float]
