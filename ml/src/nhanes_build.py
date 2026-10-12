"""Build one adult-level table from NHANES 2011-2018 (D-29).

Joins the raw CDC files (ml/data/raw/nhanes/*.xpt) on SEQN and derives:
  * the app-available inputs (docs/06 algorithm A, 12 inputs; adherence and
    days-since-last-reading do not exist in NHANES and use documented defaults),
  * the five outcomes: stroke, cad, heartFailure, ckd, t2d.

Lab values (creatinine, urine albumin) are used ONLY to define the CKD outcome,
never as model inputs, because the app never collects them.

Output: ml/data/processed/nhanes_adults.csv
Run:    ml/.venv/Scripts/python ml/src/nhanes_build.py
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

ML = Path(__file__).resolve().parents[1]
RAW = ML / "data" / "raw" / "nhanes"
OUT = ML / "data" / "processed" / "nhanes_adults.csv"
CYCLES = {"G": "2011-2012", "H": "2013-2014", "I": "2015-2016", "J": "2017-2018"}
MIN_AGE = 20  # NHANES adult questionnaire sections


def read(name: str, suffix: str, cols: list[str]) -> pd.DataFrame:
    df = pd.read_sas(RAW / f"{name}_{suffix}.xpt", format="xport", encoding="latin-1")
    return df[cols]


def yes(series: pd.Series) -> pd.Series:
    """NHANES yes/no code: 1 = yes, 2 = no, 7/9 = refused/don't know (-> missing)."""
    return series.map({1.0: 1, 2.0: 0}).astype("Float64")


def egfr_ckd_epi_2021(creatinine: pd.Series, age: pd.Series, female: pd.Series) -> pd.Series:
    """Race-free CKD-EPI 2021 eGFR (mL/min/1.73m2)."""
    kappa = np.where(female, 0.7, 0.9)
    alpha = np.where(female, -0.241, -0.302)
    ratio = creatinine / kappa
    value = (
        142
        * np.minimum(ratio, 1) ** alpha
        * np.maximum(ratio, 1) ** -1.200
        * 0.9938**age
        * np.where(female, 1.012, 1.0)
    )
    return pd.Series(value, index=creatinine.index)


def build_cycle(s: str) -> pd.DataFrame:
    demo = read("DEMO", s, ["SEQN", "RIDAGEYR", "RIAGENDR"])
    bpx = read(
        "BPX", s, ["SEQN", "BPXSY1", "BPXSY2", "BPXSY3", "BPXDI1", "BPXDI2", "BPXDI3", "BPXPLS"]
    )
    bmx = read("BMX", s, ["SEQN", "BMXBMI"])
    smq = read("SMQ", s, ["SEQN", "SMQ020", "SMQ040"])
    bpq = read("BPQ", s, ["SEQN", "BPQ020", "BPQ050A", "BPQ080"])
    mcq = read("MCQ", s, ["SEQN", "MCQ160B", "MCQ160C", "MCQ160E", "MCQ160F", "MCQ300A", "MCQ300C"])
    diq = read("DIQ", s, ["SEQN", "DIQ010", "DIQ175A"])
    kiq = read("KIQ_U", s, ["SEQN", "KIQ022"])
    rx = read("RXQ_RX", s, ["SEQN", "RXDCOUNT"]).groupby("SEQN", as_index=False).max()
    bio = read("BIOPRO", s, ["SEQN", "LBXSCR"])
    alb = read("ALB_CR", s, ["SEQN", "URDACT"])

    df = demo
    for part in (bpx, bmx, smq, bpq, mcq, diq, kiq, rx, bio, alb):
        df = df.merge(part, on="SEQN", how="left")
    df = df[df["RIDAGEYR"] >= MIN_AGE].copy()

    out = pd.DataFrame({"seqn": df["SEQN"].astype(int), "cycle": CYCLES[s]})
    out["age"] = df["RIDAGEYR"]
    out["female"] = (df["RIAGENDR"] == 2).astype(int)

    # Measured BP: mean of the available readings; 0 diastolic is a recording artefact.
    sys_cols = df[["BPXSY1", "BPXSY2", "BPXSY3"]]
    dia_cols = df[["BPXDI1", "BPXDI2", "BPXDI3"]].where(lambda d: d > 0)
    out["systolic"] = sys_cols.mean(axis=1)
    out["diastolic"] = dia_cols.mean(axis=1)
    out["heart_rate"] = df["BPXPLS"]
    out["bmi"] = df["BMXBMI"]

    # Smoking: never / former / current -> 0 / 1 / 2 (app SmokingStatus order).
    ever = yes(df["SMQ020"])
    now = df["SMQ040"].map({1.0: 1, 2.0: 1, 3.0: 0})

    def mask(cond: pd.Series) -> np.ndarray:
        return cond.fillna(False).to_numpy(dtype=bool)

    out["smoking"] = np.select(
        [mask(ever == 0), mask((ever == 1) & (now == 0)), mask((ever == 1) & (now == 1))],
        [0, 1, 2],
        np.nan,
    )

    # Family history (onboarding familyHistory): any close relative with heart attack or diabetes.
    fam = pd.concat([yes(df["MCQ300A"]), yes(df["MCQ300C"]), yes(df["DIQ175A"]).fillna(0)], axis=1)
    out["family_history"] = (fam.fillna(0).sum(axis=1) > 0).astype(int)

    # Existing conditions the app asks about at onboarding.
    out["hypertension"] = yes(df["BPQ020"])
    out["high_cholesterol"] = yes(df["BPQ080"])
    out["bp_medication"] = yes(df["BPQ050A"]).fillna(0)
    out["medication_count"] = df["RXDCOUNT"].fillna(0)

    # Outcomes.
    out["stroke"] = yes(df["MCQ160F"])
    out["cad"] = (yes(df["MCQ160C"]).fillna(0) + yes(df["MCQ160E"]).fillna(0) > 0).astype("Float64")
    out.loc[df["MCQ160C"].isna() & df["MCQ160E"].isna(), "cad"] = pd.NA
    out["heartFailure"] = yes(df["MCQ160B"])
    out["t2d"] = df["DIQ010"].map({1.0: 1, 2.0: 0, 3.0: 0}).astype("Float64")  # borderline -> no
    egfr = egfr_ckd_epi_2021(df["LBXSCR"], df["RIDAGEYR"], df["RIAGENDR"] == 2)
    ckd_lab = (egfr < 60) | (df["URDACT"] >= 30)
    ckd_self = yes(df["KIQ022"]) == 1
    has_any_kidney_info = (
        df["LBXSCR"].notna() | df["URDACT"].notna() | df["KIQ022"].isin([1.0, 2.0])
    )
    out["ckd"] = (ckd_lab | ckd_self).astype("Float64").where(has_any_kidney_info)
    return out


def main() -> None:
    frames = [build_cycle(s) for s in CYCLES]
    data = pd.concat(frames, ignore_index=True)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    data.to_csv(OUT, index=False)
    print(f"Wrote {OUT} with {len(data)} adults (age >= {MIN_AGE}).")
    print(
        data[["stroke", "cad", "heartFailure", "ckd", "t2d"]].agg(["count", "sum", "mean"]).round(3)
    )


if __name__ == "__main__":
    main()
