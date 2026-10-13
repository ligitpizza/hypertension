"""Risk model registry: loads ml/artifacts once at startup (NFR-1.2) and predicts.

docs/06 algorithm A, steps 3-4: for each complication, run the selected calibrated
model (higher-AUC of Random Forest / XGBoost, chosen during training), then categorise
the probability with the fixed cut-points from thresholds.json (D-30).

D-40 contributing factors: for XGBoost models, per-input SHAP contributions
(`pred_contribs`) averaged over the calibration folds; only inputs that raised the
estimate are kept (top FACTOR_LIMIT above FACTOR_MIN log-odds), and only for complications
at Moderate or higher.
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


FACTOR_LIMIT = 3
FACTOR_MIN = 0.02  # log-odds; smaller pushes are noise


@dataclass(frozen=True)
class ComplicationRisk:
    value: float
    level: RiskLevel
    # D-40: input names that most raised this estimate, largest first.
    factors: tuple[str, ...] = ()


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


def top_factors(contributions: list[float], names: list[str]) -> tuple[str, ...]:
    """Inputs whose contribution raised the estimate, largest first (D-40)."""
    ranked = sorted(zip(names, contributions, strict=False), key=lambda p: -p[1])
    return tuple(n for n, c in ranked if c > FACTOR_MIN)[:FACTOR_LIMIT]


def contributions(model: Any, row: np.ndarray) -> list[float] | None:
    """Mean per-input SHAP contribution over the calibration folds; None if unsupported."""
    estimators = [
        getattr(cc, "estimator", None) for cc in getattr(model, "calibrated_classifiers_", [])
    ]
    boosters = [e.get_booster() for e in estimators if e is not None and hasattr(e, "get_booster")]
    if not boosters:
        return None
    import xgboost as xgb

    matrix = xgb.DMatrix(row)
    total = np.zeros(row.shape[1])
    for booster in boosters:
        total += booster.predict(matrix, pred_contribs=True)[0][:-1]  # drop the bias term
    return [float(v) for v in total / len(boosters)]


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
            try:
                contrib = contributions(model, row)
            except Exception:  # explanations must never block a risk score
                log.exception("Contributing factors failed for %s", c.value)
                contrib = None
            level = categorise(value, self._thresholds[c])
            # D-40: explain only Moderate or higher; for near-zero risks the "raising"
            # inputs are noise (e.g. "systolic" at 89/59 nudging 0.0% up).
            factors = (
                top_factors(contrib, self._features[c])
                if contrib is not None and level is not RiskLevel.LOW
                else ()
            )
            scores[c] = ComplicationRisk(round(value, 4), level, factors)
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
        c.value: {"value": s.value, "level": s.level.value, "factors": list(s.factors)}
        for c, s in prediction.scores.items()
    }
