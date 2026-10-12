"""Write ml/REPORT.md from the trained artifacts (results for FYP Chapter 5).

Re-creates each complication's 80/20 split with the training seed, evaluates the saved
models on the untouched test set (all adults and the hypertensive subgroup) and writes
the metrics, cut-points, inputs and limitations.

Run: cd ml/src && ../.venv/Scripts/python report.py
"""

from __future__ import annotations

import json

import joblib
import pandas as pd
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import train_test_split

from feasibility import OUTCOMES
from train import ART, DATA, ML, SEED, feature_list

NAMES = {
    "stroke": "Stroke",
    "cad": "Coronary artery disease",
    "heartFailure": "Heart failure",
    "ckd": "Chronic kidney disease",
    "t2d": "Type 2 diabetes",
}


def main() -> None:
    df = pd.read_csv(DATA)
    metrics = json.loads((ART / "metrics.json").read_text())
    cuts = json.loads((ART / "thresholds.json").read_text())["cut_points"]

    rows = []
    for target in OUTCOMES:
        data = df[df[target].notna()]
        x = data[feature_list(target)].astype(float)
        y = data[target].astype(int)
        _, x_te, _, y_te = train_test_split(x, y, test_size=0.2, stratify=y, random_state=SEED)
        model = joblib.load(ART / f"{target}_model.joblib")
        p = model.predict_proba(x_te.to_numpy())[:, 1]
        hyp = (x_te["hypertension"] == 1).to_numpy()
        m = metrics[target]
        rows.append(
            {
                "target": target,
                "n": m["n_total"],
                "cases": m["cases"],
                "prev": m["prevalence"],
                "cv_rf": m["cv5_auc_train"]["rf"],
                "cv_xgb": m["cv5_auc_train"]["xgb"],
                "test_rf": m["test_auc"]["rf"],
                "test_xgb": m["test_auc"]["xgb"],
                "selected": m["selected"],
                "final": roc_auc_score(y_te, p),
                "hyp": roc_auc_score(y_te[hyp], p[hyp]),
                "hyp_n": int(hyp.sum()),
            }
        )

    lines = [
        "# CareFlow risk models — results (FR-9.2, FR-9.3, Objective 2)",
        "",
        f"Trained {metrics['meta']['trained_at']} with scikit-learn {metrics['meta']['sklearn']}"
        f" and XGBoost {metrics['meta']['xgboost']} (seed {metrics['meta']['seed']}).",
        f"Data: {metrics['meta']['dataset']}. Method: `src/train.py`; decisions D-29, D-30, D-31.",
        "",
        "## Discrimination (ROC AUC)",
        "",
        "CV = 5-fold cross-validation on the 80% training split (used for model selection);",
        "Test = untouched 20% held-out split. Final = selected model after isotonic calibration.",
        "",
        "| Complication | Adults (cases) | Prevalence | CV RF | CV XGB | Test RF | Test XGB |"
        " Selected | **Final test AUC** | ≥ 0.80 |",
        "|---|---|---|---|---|---|---|---|---|---|",
    ]
    for r in rows:
        ok = "✅" if r["final"] >= 0.80 else "⚠️ below"
        lines.append(
            f"| {NAMES[r['target']]} | {r['n']:,} ({r['cases']:,}) | {r['prev']:.1%} |"
            f" {r['cv_rf']:.3f} | {r['cv_xgb']:.3f} | {r['test_rf']:.3f} | {r['test_xgb']:.3f} |"
            f" {r['selected']} | **{r['final']:.3f}** | {ok} |"
        )
    lines += [
        "",
        "![ROC curves](reports/roc_curves.png)",
        "",
        "## Hypertensive subgroup (same held-out test set)",
        "",
        "The platform's users have hypertension. Within that subgroup the outcomes are harder",
        "to separate, so discrimination is lower; reported here as a limitation.",
        "",
        "| Complication | Hypertensive test adults | Test AUC |",
        "|---|---|---|",
    ]
    for r in rows:
        lines.append(f"| {NAMES[r['target']]} | {r['hyp_n']:,} | {r['hyp']:.3f} |")
    lines += [
        "",
        "## Risk levels (D-30)",
        "",
        "Fixed cut-points on the calibrated probability, from the 50th / 80th / 95th",
        "percentiles of predicted risk on the training split; not adjustable at runtime.",
        "",
        "| Complication | Moderate ≥ | High ≥ | Critical ≥ |",
        "|---|---|---|---|",
    ]
    for t in OUTCOMES:
        c = cuts[t]
        lines.append(
            f"| {NAMES[t]} | {c['moderate']:.1%} | {c['high']:.1%} | {c['critical']:.1%} |"
        )
    lines += [
        "",
        "## Inputs",
        "",
        "All inputs are values the app collects (D-29, D-31): age, sex, systolic and diastolic BP",
        "(mean of the last three readings), heart rate, BMI, smoking status, family history,",
        "hypertension, high cholesterol, BP medication, medication count, and the other four",
        "complications as existing conditions. Laboratory values define the CKD outcome only",
        "(eGFR CKD-EPI 2021 < 60 mL/min/1.73m² or urine ACR ≥ 30 mg/g) and are never inputs.",
        "Adherence rate and days since last reading are part of the platform's twelve inputs",
        "but are not available in NHANES, so they are not model inputs.",
        "",
        "## Limitations",
        "",
        "- Cross-sectional data: scores express association with having each complication,",
        "  not a validated 10-year incidence.",
        "- US population (NHANES); not validated on Malaysian patients (Ch1 limitation).",
        "- Outcomes other than CKD are self-reported diagnoses.",
        "- Part of the discrimination comes from existing conditions (comorbidity).",
        "- Chronic kidney disease narrowly misses the 0.80 target: CKD is defined by laboratory",
        "  tests the app does not collect.",
        "- Discrimination is lower within the hypertensive subgroup (table above).",
        "- Scores are estimates for prioritisation, not diagnoses.",
        "",
    ]
    out = ML / "REPORT.md"
    out.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {out}")
    for r in rows:
        print(f"{r['target']:13s} final={r['final']:.3f} hypertensive={r['hyp']:.3f}")


if __name__ == "__main__":
    main()
