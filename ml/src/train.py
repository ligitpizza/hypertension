"""Train the five complication risk models (FR-9.2, FR-9.3; docs/06 algorithm A; D-29).

Per complication:
  1. stratified 80/20 split; the 20% test set is untouched until final evaluation;
  2. tune Random Forest and XGBoost with randomized search + 3-fold CV on the 80%;
  3. 5-fold CV AUC of each tuned model on the 80%; select the higher (Ch4: "higher-AUC
     model selected per complication") - the test set is never used for selection;
  4. calibrate the selected model (isotonic, 5-fold) so "value" is a usable probability;
  5. fixed risk-level cut-points from the training-set predicted risk distribution
     (Low < p50 <= Moderate < p80 <= High < p95 <= Critical), stored in thresholds.json;
  6. final ROC AUC of both tuned models and the calibrated selection on the test set.

Writes ml/artifacts/: {complication}_{rf|xgb}.joblib, {complication}_model.joblib (selected,
calibrated), metrics.json, thresholds.json, feature_map.json; ROC plots in ml/reports/.

Run: ml/.venv/Scripts/python ml/src/train.py
"""

from __future__ import annotations

import json
from datetime import UTC, datetime
from pathlib import Path

import joblib
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402
import sklearn  # noqa: E402
import xgboost  # noqa: E402
from sklearn.calibration import CalibratedClassifierCV  # noqa: E402
from sklearn.ensemble import RandomForestClassifier  # noqa: E402
from sklearn.impute import SimpleImputer  # noqa: E402
from sklearn.metrics import roc_auc_score, roc_curve  # noqa: E402
from sklearn.model_selection import (  # noqa: E402
    RandomizedSearchCV,
    StratifiedKFold,
    cross_val_score,
    train_test_split,
)
from sklearn.pipeline import Pipeline  # noqa: E402
from xgboost import XGBClassifier  # noqa: E402

from feasibility import BASE, MEDICATION, OUTCOMES  # noqa: E402

ML = Path(__file__).resolve().parents[1]
DATA = ML / "data" / "processed" / "nhanes_adults.csv"
ART = ML / "artifacts"
REPORTS = ML / "reports"
SEED = 42
SEARCH_ITER = 15
LEVEL_PERCENTILES = {"moderate": 50, "high": 80, "critical": 95}


def feature_list(target: str) -> list[str]:
    """App inputs for one model; the other complications are existing conditions."""
    return BASE + MEDICATION + [o for o in OUTCOMES if o != target]


def rf_search() -> tuple[Pipeline, dict[str, list[object]]]:
    pipe = Pipeline(
        [
            ("impute", SimpleImputer(strategy="median")),
            (
                "model",
                RandomForestClassifier(
                    n_estimators=300, class_weight="balanced", n_jobs=-1, random_state=SEED
                ),
            ),
        ]
    )
    grid = {
        "model__max_depth": [None, 8, 12, 16],
        "model__min_samples_leaf": [5, 10, 20, 40],
        "model__max_features": ["sqrt", 0.5],
    }
    return pipe, grid


def xgb_search(pos_rate: float) -> tuple[XGBClassifier, dict[str, list[object]]]:
    model = XGBClassifier(
        n_estimators=400,
        scale_pos_weight=(1 - pos_rate) / pos_rate,
        eval_metric="auc",
        random_state=SEED,
        n_jobs=-1,
    )
    grid = {
        "max_depth": [3, 4, 5, 6],
        "learning_rate": [0.02, 0.05, 0.1],
        "n_estimators": [200, 400, 600],
        "subsample": [0.7, 0.9],
        "colsample_bytree": [0.6, 0.8, 1.0],
        "min_child_weight": [1, 5, 10],
    }
    return model, grid


def tune(estimator: object, grid: dict[str, list[object]], x: np.ndarray, y: np.ndarray) -> object:
    search = RandomizedSearchCV(
        estimator,
        grid,
        n_iter=SEARCH_ITER,
        scoring="roc_auc",
        cv=StratifiedKFold(3, shuffle=True, random_state=SEED),
        random_state=SEED,
        n_jobs=1,
    )
    search.fit(x, y)
    return search.best_estimator_


def main() -> None:
    df = pd.read_csv(DATA)
    ART.mkdir(exist_ok=True)
    REPORTS.mkdir(exist_ok=True)
    metrics: dict[str, object] = {}
    thresholds: dict[str, dict[str, float]] = {}
    model_used: dict[str, str] = {}
    fig, axes = plt.subplots(1, len(OUTCOMES), figsize=(4 * len(OUTCOMES), 4))

    for ax, target in zip(axes, OUTCOMES, strict=True):
        rows = df[df[target].notna()]
        cols = feature_list(target)
        x = rows[cols].astype(float).to_numpy()
        y = rows[target].astype(int).to_numpy()
        x_tr, x_te, y_tr, y_te = train_test_split(
            x, y, test_size=0.2, stratify=y, random_state=SEED
        )
        cv5 = StratifiedKFold(5, shuffle=True, random_state=SEED)

        rf = tune(*rf_search(), x_tr, y_tr)
        xgb = tune(*xgb_search(float(y_tr.mean())), x_tr, y_tr)
        cv_auc = {
            "rf": float(cross_val_score(rf, x_tr, y_tr, cv=cv5, scoring="roc_auc").mean()),
            "xgb": float(cross_val_score(xgb, x_tr, y_tr, cv=cv5, scoring="roc_auc").mean()),
        }
        rf.fit(x_tr, y_tr)
        xgb.fit(x_tr, y_tr)
        test_auc = {
            "rf": float(roc_auc_score(y_te, rf.predict_proba(x_te)[:, 1])),
            "xgb": float(roc_auc_score(y_te, xgb.predict_proba(x_te)[:, 1])),
        }
        chosen = "rf" if cv_auc["rf"] > cv_auc["xgb"] else "xgb"
        base = rf if chosen == "rf" else xgb
        calibrated = CalibratedClassifierCV(base, method="isotonic", cv=cv5)
        calibrated.fit(x_tr, y_tr)
        p_te = calibrated.predict_proba(x_te)[:, 1]
        p_tr = calibrated.predict_proba(x_tr)[:, 1]
        final_auc = float(roc_auc_score(y_te, p_te))

        joblib.dump(rf, ART / f"{target}_rf.joblib", compress=3)
        joblib.dump(xgb, ART / f"{target}_xgb.joblib", compress=3)
        joblib.dump(calibrated, ART / f"{target}_model.joblib", compress=3)

        thresholds[target] = {
            level: float(np.percentile(p_tr, pct)) for level, pct in LEVEL_PERCENTILES.items()
        }
        name = "RandomForest" if chosen == "rf" else "XGBoost"
        model_used[target] = f"{name} v1"
        metrics[target] = {
            "n_total": int(len(y)),
            "cases": int(y.sum()),
            "prevalence": round(float(y.mean()), 4),
            "cv5_auc_train": {k: round(v, 4) for k, v in cv_auc.items()},
            "test_auc": {k: round(v, 4) for k, v in test_auc.items()},
            "selected": name,
            "selected_calibrated_test_auc": round(final_auc, 4),
            "meets_target_0_80": final_auc >= 0.80,
        }
        print(
            f"{target:13s} CV rf={cv_auc['rf']:.3f} xgb={cv_auc['xgb']:.3f} | "
            f"test rf={test_auc['rf']:.3f} xgb={test_auc['xgb']:.3f} | "
            f"selected {name} calibrated test AUC={final_auc:.3f}",
            flush=True,
        )

        fpr, tpr, _ = roc_curve(y_te, p_te)
        ax.plot(fpr, tpr, label=f"{name} AUC={final_auc:.3f}")
        ax.plot([0, 1], [0, 1], "--", color="grey", linewidth=1)
        ax.set_title(target)
        ax.set_xlabel("False positive rate")
        ax.set_ylabel("True positive rate")
        ax.legend(loc="lower right")

    fig.tight_layout()
    fig.savefig(REPORTS / "roc_curves.png", dpi=120)

    meta = {
        "trained_at": datetime.now(UTC).isoformat(timespec="seconds"),
        "dataset": "NHANES 2011-2018 adults (age >= 20), US CDC, public domain (D-29)",
        "sklearn": sklearn.__version__,
        "xgboost": xgboost.__version__,
        "seed": SEED,
    }
    (ART / "metrics.json").write_text(json.dumps({"meta": meta, **metrics}, indent=2))
    (ART / "thresholds.json").write_text(
        json.dumps(
            {
                "rule": "Low < moderate <= Moderate < high <= High < critical <= Critical",
                "percentiles": LEVEL_PERCENTILES,
                "cut_points": thresholds,
            },
            indent=2,
        )
    )
    (ART / "feature_map.json").write_text(
        json.dumps(
            {
                "model_used": model_used,
                "features": {t: feature_list(t) for t in OUTCOMES},
            },
            indent=2,
        )
    )
    print(f"Saved artifacts to {ART}")


if __name__ == "__main__":
    main()
