# CareFlow ML pipeline (Module 9, FR-9.2 / FR-9.3)

Trains the five hypertension-complication risk models (stroke, coronary artery disease,
heart failure, chronic kidney disease, type 2 diabetes) with Random Forest and XGBoost,
selects the higher-AUC model per complication, calibrates it and fixes the risk-level
cut-points (docs/06 algorithm A; decisions D-04, D-29, D-30).

## Data (D-29)

**NHANES 2011–2018**, US Centers for Disease Control and Prevention (public domain), four
cycles (G, H, I, J), adults aged 20+. Raw files are not committed; download them from
`https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/<year>/DataFiles/<FILE>_<cycle>.xpt`
into `ml/data/raw/nhanes/`:

| File | Used for |
|---|---|
| DEMO | age, sex |
| BPX | measured systolic / diastolic BP, pulse |
| BMX | BMI |
| SMQ | smoking status |
| BPQ | diagnosed hypertension, high cholesterol, BP medication |
| MCQ | outcomes: stroke, coronary heart disease / heart attack, heart failure; family history |
| DIQ | outcome: diabetes; family history of diabetes |
| KIQ_U | self-reported weak/failing kidneys (CKD outcome) |
| RXQ_RX | number of prescription medicines |
| BIOPRO, ALB_CR | serum creatinine, urine albumin/creatinine — **CKD label only** (eGFR CKD-EPI 2021 < 60 or ACR ≥ 30), never model inputs |

Model inputs are only values the app can collect: age, sex, systolic, diastolic, heart
rate, BMI, smoking, family history, hypertension, high cholesterol, BP medication,
medication count, and the other four complications as existing conditions. Adherence and
days-since-last-reading are part of the platform's 12 inputs but do not exist in NHANES;
they are recorded with each score but not used by these models.

## Run

```bash
python -m venv ml/.venv
ml/.venv/Scripts/python -m pip install -r ml/requirements.txt
ml/.venv/Scripts/python ml/src/nhanes_build.py   # -> ml/data/processed/nhanes_adults.csv
ml/.venv/Scripts/python ml/src/feasibility.py    # 5-fold CV AUC overview
cd ml/src && ../.venv/Scripts/python train.py    # -> ml/artifacts/, ml/reports/roc_curves.png
```

## Outputs

- `artifacts/{complication}_{rf|xgb}.joblib` — tuned models (git-ignored; reproducible)
- `artifacts/{complication}_model.joblib` — selected, calibrated model loaded by FastAPI
- `artifacts/metrics.json` — CV and held-out test AUC per model, selection, target check
- `artifacts/thresholds.json` — fixed Low/Moderate/High/Critical cut-points (D-30)
- `artifacts/feature_map.json` — input order per model, model used
- `reports/roc_curves.png`, `REPORT.md` — results for Chapter 5

## Limitations (state these in Chapter 5)

- NHANES is cross-sectional: models estimate how strongly a profile is associated with
  having each complication, not a validated 10-year incidence.
- US population; not validated on Malaysian patients (Ch1 limitation).
- Outcomes other than CKD are self-reported diagnoses.
- Part of the discrimination comes from existing conditions (comorbidity).
- Discrimination is lower within the hypertensive subgroup (see REPORT.md).
- Not a diagnostic tool; the app presents scores as estimates.
