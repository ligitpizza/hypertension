"""Risk model registry: loads ml/artifacts once at startup (NFR-1.2) and predicts.

docs/06 algorithm A, steps 3-4: for each complication, run the selected calibrated
model (higher-AUC of Random Forest / XGBoost, chosen during training), then categorise
the probability with the fixed cut-points from thresholds.json (D-30).
"""

from __future__ import annotations

import json
import logging
import math
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any, Protocol

import joblib
import numpy as np

from app.core.config import get_settings
from app.core.enums import Complication, RiskLevel

log = logging.getLogger("careflow.ml")


@dataclass(frozen=True)
class ComplicationRisk:
    value: float
    level: RiskLevel


@dataclass(frozen=True)
class RiskPrediction:
    scores: dict[Complication, ComplicationRisk]
    model_used: str

    @property
    def overall_level(self) -> RiskLevel:
        """D-03: highest of the five levels."""
        order = list(RiskLevel)
        return max((s.level for s in self.scores.values()), key=order.index)


class Predictor(Protocol):
    def predict_proba(self, x: np.ndarray) -> np.ndarray: ...


def categorise(value: float, cut: dict[str, float]) -> RiskLevel:
    if value >= cut["critical"]:
        return RiskLevel.CRITICAL
    if value >= cut["high"]:
        return RiskLevel.HIGH
    if value >= cut["moderate"]:
        return RiskLevel.MODERATE
    return RiskLevel.LOW


class RiskModel:
    def __init__(
        self,
        models: dict[Complication, Predictor],
        features: dict[Complication, list[str]],
        thresholds: dict[Complication, dict[str, float]],
        model_used: dict[Complication, str],
    ) -> None:
        self._models = models
        self._features = features
        self._thresholds = thresholds
        self._model_used = model_used

    @classmethod
    def load(cls, directory: Path) -> RiskModel:
        fmap = json.loads((directory / "feature_map.json").read_text(encoding="utf-8"))
        cuts = json.loads((directory / "thresholds.json").read_text(encoding="utf-8"))
        models: dict[Complication, Predictor] = {}
        features: dict[Complication, list[str]] = {}
        thresholds: dict[Complication, dict[str, float]] = {}
        used: dict[Complication, str] = {}
        for c in Complication:
            models[c] = joblib.load(directory / f"{c.value}_model.joblib")
            features[c] = list(fmap["features"][c.value])
            thresholds[c] = {k: float(v) for k, v in cuts["cut_points"][c.value].items()}
            used[c] = str(fmap["model_used"][c.value])
        return cls(models, features, thresholds, used)

    def predict(self, inputs: dict[str, float]) -> RiskPrediction:
        scores: dict[Complication, ComplicationRisk] = {}
        for c, model in self._models.items():
            row = np.array([[inputs.get(f, math.nan) for f in self._features[c]]], dtype=float)
            value = float(model.predict_proba(row)[0, 1])
            scores[c] = ComplicationRisk(round(value, 4), categorise(value, self._thresholds[c]))
        used = "; ".join(f"{c.value}:{self._model_used[c]}" for c in Complication)
        return RiskPrediction(scores=scores, model_used=used)


@lru_cache
def _cached_model(directory: str) -> RiskModel:
    return RiskModel.load(Path(directory))


def load_risk_model() -> RiskModel | None:
    """Called at startup; returns None (and logs) if artifacts are missing."""
    try:
        return _cached_model(str(get_settings().ml_artifacts_dir))
    except (OSError, KeyError, ValueError) as exc:
        log.warning("Risk models not loaded from %s: %s", get_settings().ml_artifacts_dir, exc)
        return None


def get_risk_model() -> RiskModel | None:
    """FastAPI dependency; None when artifacts are missing (readings are still saved)."""
    return load_risk_model()


def scores_document(prediction: RiskPrediction) -> dict[str, Any]:
    """risk_scores.scores map in the Ch4 shape: {stroke: {value, level}, ...}."""
    return {
        c.value: {"value": s.value, "level": s.level.value} for c, s in prediction.scores.items()
    }
