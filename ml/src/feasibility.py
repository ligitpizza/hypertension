"""Feasibility check (D-29): what AUC each complication honestly reaches with app inputs.

Stratified 5-fold cross-validated ROC AUC for Random Forest and XGBoost on the NHANES
adult table, using only inputs the app can supply. Reported for all adults and for
adults with hypertension, and with/without the medication inputs (medication count and
BP medication can partly reflect an existing diagnosis, so their effect is shown).

Run: ml/.venv/Scripts/python ml/src/feasibility.py
"""

from __future__ import annotations

from pathlib import Path

import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.model_selection import StratifiedKFold, cross_val_score
from sklearn.pipeline import make_pipeline
from xgboost import XGBClassifier

ML = Path(__file__).resolve().parents[1]
DATA = ML / "data" / "processed" / "nhanes_adults.csv"

OUTCOMES = ["stroke", "cad", "heartFailure", "ckd", "t2d"]
BASE = [
    "age",
    "female",
    "systolic",
    "diastolic",
    "heart_rate",
    "bmi",
    "smoking",
    "family_history",
    "hypertension",
    "high_cholesterol",
]
MEDICATION = ["bp_medication", "medication_count"]
SEED = 42


def features(target: str, with_meds: bool) -> list[str]:
    # The other complications are "existing conditions" the app collects at onboarding.
    others = [o for o in OUTCOMES if o != target]
    return BASE + (MEDICATION if with_meds else []) + others


def models(pos_rate: float) -> dict[str, object]:
    return {
        "RF": make_pipeline(
            SimpleImputer(strategy="median"),
            RandomForestClassifier(
                n_estimators=300,
                min_samples_leaf=20,
                class_weight="balanced",
                n_jobs=-1,
                random_state=SEED,
            ),
        ),
        "XGB": XGBClassifier(
            n_estimators=300,
            max_depth=4,
            learning_rate=0.05,
            subsample=0.8,
            colsample_bytree=0.8,
            scale_pos_weight=(1 - pos_rate) / pos_rate,
            eval_metric="auc",
            random_state=SEED,
            n_jobs=-1,
        ),
    }


def evaluate(df: pd.DataFrame, target: str, with_meds: bool) -> dict[str, str]:
    rows = df[df[target].notna()]
    x = rows[features(target, with_meds)].astype(float)
    y = rows[target].astype(int)
    cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=SEED)
    out = {"n": str(len(rows)), "cases": str(int(y.sum()))}
    for name, model in models(y.mean()).items():
        scores = cross_val_score(model, x, y, cv=cv, scoring="roc_auc", n_jobs=1)
        out[name] = f"{scores.mean():.3f}±{scores.std():.3f}"
    return out


def main() -> None:
    df = pd.read_csv(DATA)
    groups = {"all adults": df, "hypertensive adults": df[df["hypertension"] == 1]}
    rows = []
    for group, data in groups.items():
        for target in OUTCOMES:
            for with_meds in (True, False):
                r = evaluate(data, target, with_meds)
                rows.append({"group": group, "target": target, "medication inputs": with_meds, **r})
    table = pd.DataFrame(rows)
    print(table.to_string(index=False))


if __name__ == "__main__":
    main()
