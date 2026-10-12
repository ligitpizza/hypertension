"""CareFlow developer tasks (D-24): a cross-platform replacement for make and .sh scripts.

Usage:  python tasks.py <task> [--yes]

Local tasks
  emulators        Start the Firebase Emulator Suite (Auth, Firestore, Storage, UI),
                   importing/exporting firebase/seed-data
  seed             Seed the running emulators (symptom_catalog + demo accounts)
  api              Run FastAPI locally with reload (backend/.venv, backend/.env)
  test             flutter test + pytest + Firestore rules tests
  lint             flutter analyze + ruff + ruff format --check + mypy

Cloud tasks (print the exact command and require --yes; project hypertension-dd85f)
  deploy-backend          Cloud Run service careflow-api (asia-southeast1, max 2 instances)
  deploy-web              Build the staff portal and deploy Firebase Hosting
  deploy-rules            Firestore rules + indexes and Storage rules
  create-scheduler-jobs   Idempotent Cloud Scheduler jobs calling /internal/jobs/*
  build-apk               Release APKs for the patient and family flavors
  backend-url             Print the deployed Cloud Run URL
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
APP = ROOT / "app"
BACKEND = ROOT / "backend"
FIREBASE = ROOT / "firebase"
ML_ARTIFACTS = ROOT / "ml" / "artifacts"

PROJECT_ID = "hypertension-dd85f"
REGION = "asia-southeast1"
SERVICE = "careflow-api"
SCHEDULER_SA_NAME = "careflow-scheduler"
SCHEDULER_SA = f"{SCHEDULER_SA_NAME}@{PROJECT_ID}.iam.gserviceaccount.com"
# Fixed OIDC audience checked by backend/app/routers/jobs.py (no URL chicken-and-egg).
JOBS_AUDIENCE = "careflow-internal-jobs"
TIMEZONE = "Asia/Kuala_Lumpur"
# demo- prefix: emulator-only project, can never reach the cloud (rules tests).
RULES_TEST_PROJECT = "demo-careflow-rules"

# name -> (cron schedule, job path). Keep this list small (docs/10 cost controls).
SCHEDULER_JOBS: dict[str, tuple[str, str]] = {
    "careflow-heartbeat": ("0 3 * * *", "heartbeat"),
}

EMULATOR_ENV = {
    "FIRESTORE_EMULATOR_HOST": "localhost:8080",
    "FIREBASE_AUTH_EMULATOR_HOST": "localhost:9099",
    "FIREBASE_STORAGE_EMULATOR_HOST": "localhost:9199",
    "GOOGLE_CLOUD_PROJECT": PROJECT_ID,
}

ASSUME_YES = "--yes" in sys.argv


def venv_python() -> str:
    win = BACKEND / ".venv" / "Scripts" / "python.exe"
    nix = BACKEND / ".venv" / "bin" / "python"
    for p in (win, nix):
        if p.exists():
            return str(p)
    sys.exit("backend/.venv not found. Create it: python -m venv backend/.venv")


def exe(name: str) -> str:
    """Resolve a CLI (handles Windows .cmd/.bat shims)."""
    found = shutil.which(name)
    if not found:
        sys.exit(f"'{name}' not found on PATH.")
    return found


def run(cmd: list[str], cwd: Path = ROOT, env: dict[str, str] | None = None) -> None:
    print(f"\n> {' '.join(cmd)}   (in {cwd.relative_to(ROOT) if cwd != ROOT else '.'})", flush=True)
    full_env = {**os.environ, **(env or {})}
    result = subprocess.run(cmd, cwd=cwd, env=full_env, check=False)  # noqa: S603
    if result.returncode != 0:
        sys.exit(result.returncode)


def capture(cmd: list[str], cwd: Path = ROOT) -> tuple[int, str]:
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=False)  # noqa: S603
    return r.returncode, r.stdout.strip()


def confirm_cloud(description: str, cmds: list[list[str]]) -> None:
    print(f"CLOUD ACTION: {description}")
    for c in cmds:
        print("   " + " ".join(c))
    if not ASSUME_YES:
        sys.exit("Not run. Re-run with --yes to execute.")


# ---------------- local ----------------


def task_emulators() -> None:
    seed_data = FIREBASE / "seed-data"
    cmd = [
        exe("firebase"),
        "emulators:start",
        "--project",
        PROJECT_ID,
        "--export-on-exit=./seed-data",
    ]
    if seed_data.exists():
        cmd.insert(2, "--import=./seed-data")
    else:
        print(
            "No firebase/seed-data yet: starting empty. Run `python tasks.py seed` once it is up."
        )
    run(cmd, cwd=FIREBASE)


def task_seed() -> None:
    run([venv_python(), str(FIREBASE / "seed" / "seed.py")], env=EMULATOR_ENV)


def task_api() -> None:
    env_file = BACKEND / ".env"
    if not env_file.exists():
        sys.exit("backend/.env missing. Copy backend/.env.example to backend/.env.")
    run(
        [
            venv_python(),
            "-m",
            "uvicorn",
            "app.main:app",
            "--reload",
            "--host",
            "0.0.0.0",  # noqa: S104  (Android emulator reaches the host via 10.0.2.2)
            "--port",
            "8000",
            "--env-file",
            ".env",
        ],
        cwd=BACKEND,
    )


def task_test() -> None:
    run([exe("flutter"), "test"], cwd=APP)
    run([venv_python(), "-m", "pytest"], cwd=BACKEND)
    rules_tests = FIREBASE / "tests"
    if (rules_tests / "node_modules").exists():
        run(
            [
                exe("firebase"),
                "emulators:exec",
                "--project",
                RULES_TEST_PROJECT,
                "--only",
                "firestore,storage",
                "npm --prefix tests test",
            ],
            cwd=FIREBASE,
        )
    else:
        print("\n(skipping rules tests: run `npm install` in firebase/tests first)")


def task_lint() -> None:
    run([exe("flutter"), "analyze"], cwd=APP)
    py = venv_python()
    py_paths = [".", "../tasks.py", "../firebase/seed"]
    run([py, "-m", "ruff", "check", *py_paths], cwd=BACKEND)
    run([py, "-m", "ruff", "format", "--check", *py_paths], cwd=BACKEND)
    run([py, "-m", "mypy", "app", "tests"], cwd=BACKEND)


# ---------------- cloud ----------------


def backend_url() -> str:
    code, out = capture(
        [
            exe("gcloud"),
            "run",
            "services",
            "describe",
            SERVICE,
            "--region",
            REGION,
            "--project",
            PROJECT_ID,
            "--format=value(status.url)",
        ]
    )
    return out if code == 0 else ""


def task_backend_url() -> None:
    print(backend_url() or "(service not deployed yet)")


def task_deploy_backend() -> None:
    env_vars = ",".join(
        [
            "APP_ENV=prod",
            "INTEGRATIONS_MODE=fake",
            "INTERNAL_JOBS_AUTH=oidc",
            f"JOBS_OIDC_AUDIENCE={JOBS_AUDIENCE}",
            f"JOBS_SERVICE_ACCOUNT={SCHEDULER_SA}",
            f"FIREBASE_PROJECT_ID={PROJECT_ID}",
        ]
    )
    cmd = [
        exe("gcloud"),
        "run",
        "deploy",
        SERVICE,
        "--source",
        "backend",
        "--project",
        PROJECT_ID,
        "--region",
        REGION,
        "--min-instances",
        "0",
        "--max-instances",
        "2",
        "--memory",
        "1Gi",
        "--cpu",
        "1",
        "--concurrency",
        "20",
        "--allow-unauthenticated",
        "--set-env-vars",
        env_vars,
    ]
    confirm_cloud("deploy FastAPI to Cloud Run (Cloud Build builds backend/Dockerfile)", [cmd])
    target = BACKEND / "ml_artifacts"
    if ML_ARTIFACTS.exists():
        for f in ML_ARTIFACTS.iterdir():
            if f.is_file():
                shutil.copy2(f, target / f.name)
    run(cmd)


def task_deploy_web() -> None:
    build = [exe("flutter"), "build", "web", "--release", "-t", "lib/main_staff.dart"]
    deploy = [exe("firebase"), "deploy", "--only", "hosting", "--project", PROJECT_ID]
    confirm_cloud("build the staff portal and deploy Firebase Hosting", [build, deploy])
    run(build, cwd=APP)
    run(deploy, cwd=FIREBASE)


def task_deploy_rules() -> None:
    cmd = [
        exe("firebase"),
        "deploy",
        "--only",
        "firestore:rules,firestore:indexes,storage",
        "--project",
        PROJECT_ID,
    ]
    confirm_cloud("deploy Firestore rules/indexes and Storage rules", [cmd])
    run(cmd, cwd=FIREBASE)


def task_create_scheduler_jobs() -> None:
    url = backend_url()
    if not url:
        sys.exit("Cloud Run service not found. Run deploy-backend first.")
    gcloud = exe("gcloud")
    plans: list[list[str]] = []
    for name, (schedule, job) in SCHEDULER_JOBS.items():
        code, _ = capture(
            [
                gcloud,
                "scheduler",
                "jobs",
                "describe",
                name,
                "--location",
                REGION,
                "--project",
                PROJECT_ID,
            ]
        )
        verb = "update" if code == 0 else "create"
        plans.append(
            [
                gcloud,
                "scheduler",
                "jobs",
                verb,
                "http",
                name,
                "--location",
                REGION,
                "--project",
                PROJECT_ID,
                "--schedule",
                schedule,
                "--time-zone",
                TIMEZONE,
                "--uri",
                f"{url}/internal/jobs/{job}",
                "--http-method",
                "POST",
                "--oidc-service-account-email",
                SCHEDULER_SA,
                "--oidc-token-audience",
                JOBS_AUDIENCE,
            ]
        )
    code, _ = capture(
        [gcloud, "iam", "service-accounts", "describe", SCHEDULER_SA, "--project", PROJECT_ID]
    )
    if code != 0:
        plans.insert(
            0,
            [
                gcloud,
                "iam",
                "service-accounts",
                "create",
                SCHEDULER_SA_NAME,
                "--project",
                PROJECT_ID,
                "--display-name",
                "CareFlow Cloud Scheduler (OIDC caller)",
            ],
        )
    confirm_cloud(
        "create/update Cloud Scheduler jobs (and the caller service account if missing)", plans
    )
    for p in plans:
        run(p)


def task_build_apk() -> None:
    url = backend_url()
    if not url:
        sys.exit("Cloud Run service not found. Run deploy-backend first.")
    cmds = [
        [
            exe("flutter"),
            "build",
            "apk",
            "--release",
            "--flavor",
            flavor,
            "-t",
            f"lib/main_{flavor}.dart",
            f"--dart-define=API_BASE_URL={url}",
        ]
        for flavor in ("patient", "family")
    ]
    for c in cmds:
        run(c, cwd=APP)


TASKS = {
    "emulators": task_emulators,
    "seed": task_seed,
    "api": task_api,
    "test": task_test,
    "lint": task_lint,
    "deploy-backend": task_deploy_backend,
    "deploy-web": task_deploy_web,
    "deploy-rules": task_deploy_rules,
    "create-scheduler-jobs": task_create_scheduler_jobs,
    "build-apk": task_build_apk,
    "backend-url": task_backend_url,
}


def main() -> None:
    args = [a for a in sys.argv[1:] if a != "--yes"]
    if not args or args[0] not in TASKS:
        print(__doc__)
        sys.exit(0 if not args else 1)
    TASKS[args[0]]()


if __name__ == "__main__":
    main()
