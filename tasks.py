"""Harvey developer tasks (D-24): a cross-platform replacement for make and .sh scripts.

Usage:  python tasks.py <task> [--yes]

Local tasks
  dev              ONE command: emulators + seed (if needed) + FastAPI + app on phone
                   (or double-click dev.cmd). Ctrl+C once stops everything.
  emulators        Start the Firebase Emulator Suite (Auth, Firestore, Storage, UI),
                   importing/exporting firebase/seed-data
  seed             Seed the running emulators (symptom_catalog + demo accounts)
  api              Run FastAPI locally with reload (backend/.venv, backend/.env)
  firebase-config  Generate google-services.json files from app/.env (run after cloning)
  adb-reverse      Physical phone over USB: forward ports 8000/9099/8080/9199 to this PC
  phone-install    Build, install and open the app on a USB phone without the debugger
                   (python tasks.py phone-install [patient|family])
  test             flutter test + pytest + Firestore rules tests
  lint             flutter analyze + ruff + ruff format --check + mypy

Cloud tasks (print the exact command and require --yes; project hypertension-dd85f)
  deploy-all              Everything below in order: rules -> backend -> web -> scheduler
                          jobs (or double-click deploy-all.cmd; asks once to confirm)
  deploy-backend          Cloud Run service careflow-api (asia-southeast1, max 2 instances)
  deploy-web              Build the staff portal and deploy Firebase Hosting
  deploy-rules            Firestore rules + indexes and Storage rules
  set-storage-cors        Let the staff portal (browser) download message attachments
                          (idempotent; firebase/storage.cors.json; also run by deploy-all)
  create-scheduler-jobs   Idempotent Cloud Scheduler jobs calling /internal/jobs/*
  seed-catalog-live       Write symptom_catalog and the medication catalogue (+ demo stock)
                          to the live project (idempotent; also run by deploy-all)
  set-brevo-secret        One-time (and when the key changes): store EMAIL_API_KEY (Brevo
                          email + SMS) from backend/.env in Secret Manager for Cloud Run
  set-gemini-secret       One-time (and when the key changes): store GEMINI_API_KEY from
                          backend/.env in Secret Manager for the live AI agent
  set-stripe-secrets      One-time (D-66): store the Stripe TEST secret key (and webhook
                          secret, if set) from backend/.env in Secret Manager
  set-grab-secrets        One-time (D-67): store the GrabExpress sandbox client secret (and
                          webhook token, if set) from backend/.env in Secret Manager
  set-lalamove-secrets    One-time (D-68): store the Lalamove sandbox API secret from
                          backend/.env in Secret Manager
  build-apk               Release APKs for the patient and family flavors
  phone-live              Build release apps and install the live-cloud patient app on
                          the phone (or double-click phone-live.cmd)
  bootstrap-admin         One-time: create the first admin in the live project
                          (python tasks.py bootstrap-admin you@example.com "Name" --yes)
  backend-url             Print the deployed Cloud Run URL
"""

from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import sys
import time
import urllib.request
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
# Secret Manager secret holding the Gemini key (FR-14.1); created by set-gemini-secret.
GEMINI_SECRET = "gemini-api-key"
# Brevo key for real email and SMS (D-22, D-64); created by set-brevo-secret.
BREVO_SECRET = "brevo-api-key"
# Stripe TEST keys for Module 13 payments (D-66); created by set-stripe-secrets.
STRIPE_SECRET = "stripe-secret-key"
STRIPE_WEBHOOK_SECRET = "stripe-webhook-secret"
# GrabExpress sandbox OAuth secret and webhook token (D-67); created by set-grab-secrets.
GRAB_SECRET = "grab-client-secret"
GRAB_WEBHOOK_SECRET = "grab-webhook-secret"
# Lalamove sandbox API secret (D-68); created by set-lalamove-secrets.
LALAMOVE_SECRET = "lalamove-api-secret"
# demo- prefix: emulator-only project, can never reach the cloud (rules tests).
RULES_TEST_PROJECT = "demo-careflow-rules"

# name -> (cron schedule, job path). Keep this list small (docs/10 cost controls).
SCHEDULER_JOBS: dict[str, tuple[str, str]] = {
    "careflow-heartbeat": ("0 3 * * *", "heartbeat"),
    # FR-9.6: daily 30-day deterioration scan.
    "careflow-deterioration": ("0 6 * * *", "deterioration"),
    # D-37: escalate high alerts unanswered for 2 h (Cloud Scheduler free tier: 3 jobs).
    "careflow-escalation": ("*/15 * * * *", "escalation"),
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
    print(
        f"\n> {' '.join(cmd)}   (in {cwd.relative_to(ROOT) if cwd != ROOT else '.'})",
        flush=True,
    )
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


def emulator_command() -> list[str]:
    cmd = [
        exe("firebase"),
        "emulators:start",
        "--project",
        PROJECT_ID,
        "--export-on-exit=./seed-data",
    ]
    if (FIREBASE / "seed-data").exists():
        cmd.insert(2, "--import=./seed-data")
    return cmd


def task_emulators() -> None:
    if not (FIREBASE / "seed-data").exists():
        print(
            "No firebase/seed-data yet: starting empty. Run `python tasks.py seed` once it is up."
        )
    run(emulator_command(), cwd=FIREBASE)


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
    # Backend services against the Auth + Firestore emulators (skipped in plain pytest).
    python = Path("..") / Path(venv_python()).relative_to(ROOT)
    run(
        [
            exe("firebase"),
            "emulators:exec",
            "--project",
            PROJECT_ID,
            "--only",
            "auth,firestore",
            f"cd ../backend && {python} -m pytest tests/test_integration_emulator.py",
        ],
        cwd=FIREBASE,
    )


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


def _local_env(key: str) -> str:
    """A value from backend/.env (never printed)."""
    env_file = BACKEND / ".env"
    if not env_file.exists():
        return ""
    for line in env_file.read_text(encoding="utf-8").splitlines():
        if line.startswith(f"{key}="):
            return line.split("=", 1)[1].strip()
    return ""


def _secret_exists(name: str) -> bool:
    code, _ = capture(
        [
            exe("gcloud"),
            "secrets",
            "describe",
            name,
            "--project",
            PROJECT_ID,
            "--format=value(name)",
        ]
    )
    return code == 0


def _store_secret(secret: str, env_key: str, what: str) -> None:
    """Store [env_key] from backend/.env in Secret Manager as [secret], readable only by the
    Cloud Run service account. The value goes over stdin and is never printed."""
    key = _local_env(env_key)
    if not key:
        sys.exit(f"{env_key} is empty in backend/.env. Add it there first.")
    gcloud = exe("gcloud")
    code, number = capture(
        [gcloud, "projects", "describe", PROJECT_ID, "--format=value(projectNumber)"]
    )
    if code != 0 or not number:
        sys.exit("Could not read the project number. Run `gcloud auth login` first.")
    runtime_sa = f"{number}-compute@developer.gserviceaccount.com"  # Cloud Run default
    enable = [
        gcloud,
        "services",
        "enable",
        "secretmanager.googleapis.com",
        "--project",
        PROJECT_ID,
    ]
    exists = _secret_exists(secret) if ASSUME_YES else False
    create = [
        gcloud,
        "secrets",
        "create",
        secret,
        "--project",
        PROJECT_ID,
        "--replication-policy=user-managed",
        f"--locations={REGION}",
    ]
    add_version = [
        gcloud,
        "secrets",
        "versions",
        "add",
        secret,
        "--project",
        PROJECT_ID,
        "--data-file=-",
    ]
    grant = [
        gcloud,
        "secrets",
        "add-iam-policy-binding",
        secret,
        "--project",
        PROJECT_ID,
        f"--member=serviceAccount:{runtime_sa}",
        "--role=roles/secretmanager.secretAccessor",
    ]
    confirm_cloud(
        f"enable Secret Manager and store the {what} from backend/.env as secret "
        f"'{secret}' ({REGION}), readable only by the Cloud Run service account "
        "(the key is passed on stdin and never printed)",
        [enable, create, add_version + ["   <- key from backend/.env on stdin"], grant],
    )
    run(enable)
    if not exists and not _secret_exists(secret):
        run(create)
    print(f"\n> {' '.join(add_version)}   (key from backend/.env on stdin)", flush=True)
    result = subprocess.run(add_version, input=key, text=True, check=False)
    if result.returncode != 0:
        sys.exit(result.returncode)
    run(grant)
    print("\nDone. Now run deploy-backend (or deploy-all) so Cloud Run uses the secret.")


def task_set_gemini_secret() -> None:
    """Store GEMINI_API_KEY from backend/.env in Secret Manager for Cloud Run (FR-14.1)."""
    _store_secret(GEMINI_SECRET, "GEMINI_API_KEY", "Gemini key")


def task_set_brevo_secret() -> None:
    """Store EMAIL_API_KEY (Brevo: email and SMS) for Cloud Run (D-22, D-64)."""
    _store_secret(BREVO_SECRET, "EMAIL_API_KEY", "Brevo API key")


def task_set_stripe_secrets() -> None:
    """Store STRIPE_SECRET_KEY (and STRIPE_WEBHOOK_SECRET when set) for Cloud Run (D-66).
    Test-mode keys only; the backend refuses live keys."""
    key = _local_env("STRIPE_SECRET_KEY")
    if key and not key.startswith("sk_test_"):
        sys.exit("STRIPE_SECRET_KEY must be a test key (sk_test_...). Live keys are not allowed.")
    _store_secret(STRIPE_SECRET, "STRIPE_SECRET_KEY", "Stripe test secret key")
    if _local_env("STRIPE_WEBHOOK_SECRET"):
        _store_secret(STRIPE_WEBHOOK_SECRET, "STRIPE_WEBHOOK_SECRET", "Stripe webhook secret")
    else:
        print("No STRIPE_WEBHOOK_SECRET yet; the app confirms payments by asking Stripe instead.")


def task_set_grab_secrets() -> None:
    """Store GRAB_CLIENT_SECRET (and GRAB_WEBHOOK_SECRET when set) for Cloud Run (D-67)."""
    _store_secret(GRAB_SECRET, "GRAB_CLIENT_SECRET", "GrabExpress sandbox client secret")
    if _local_env("GRAB_WEBHOOK_SECRET"):
        _store_secret(GRAB_WEBHOOK_SECRET, "GRAB_WEBHOOK_SECRET", "Grab webhook token")
    else:
        print("No GRAB_WEBHOOK_SECRET yet; delivery status is read from Grab instead.")


def task_set_lalamove_secrets() -> None:
    """Store LALAMOVE_API_SECRET for Cloud Run (D-68). Sandbox keys only."""
    secret = _local_env("LALAMOVE_API_SECRET")
    if secret and not secret.startswith("sk_test"):
        sys.exit("LALAMOVE_API_SECRET must be a sandbox key (sk_test_...).")
    _store_secret(LALAMOVE_SECRET, "LALAMOVE_API_SECRET", "Lalamove sandbox API secret")


def task_deploy_backend() -> None:
    brevo = _secret_exists(BREVO_SECRET)
    stripe = _secret_exists(STRIPE_SECRET)
    # gcloud's "^##^" prefix switches the separator, so values may contain commas (addresses).
    env_vars = "^##^" + "##".join(
        [
            "APP_ENV=prod",
            # D-64/D-66: real adapters once a key is in Secret Manager (each adapter still
            # falls back to its fake when its own key is missing).
            f"INTEGRATIONS_MODE={'real' if brevo or stripe else 'fake'}",
            f"EMAIL_FROM={_local_env('EMAIL_FROM')}",
            f"EMAIL_FROM_NAME={_local_env('EMAIL_FROM_NAME') or 'Harvey'}",
            f"SMS_SENDER={_local_env('SMS_SENDER')}",
            "INTERNAL_JOBS_AUTH=oidc",
            f"JOBS_OIDC_AUDIENCE={JOBS_AUDIENCE}",
            f"JOBS_SERVICE_ACCOUNT={SCHEDULER_SA}",
            f"FIREBASE_PROJECT_ID={PROJECT_ID}",
            "ML_ARTIFACTS_DIR=/srv/ml_artifacts",
            "FCM_ENABLED=true",
            f"GEMINI_MODEL={_local_env('GEMINI_MODEL') or 'gemini-3.1-flash-lite'}",
            # D-57 testing aid; set DEV_APPOINTMENT_TIMES=false in backend/.env for real use.
            f"DEV_APPOINTMENT_TIMES={_local_env('DEV_APPOINTMENT_TIMES') or 'false'}",
            # D-66: publishable key is public by design; the secret key goes via Secret Manager.
            f"STRIPE_PUBLISHABLE_KEY={_local_env('STRIPE_PUBLISHABLE_KEY')}",
            # D-66 testing aid; set DEV_ORDER_TOOLS=false in backend/.env for real use.
            f"DEV_ORDER_TOOLS={_local_env('DEV_ORDER_TOOLS') or 'false'}",
            # D-78 testing aid; set DEV_VITALS_TOOLS=false in backend/.env for real use.
            f"DEV_VITALS_TOOLS={_local_env('DEV_VITALS_TOOLS') or 'false'}",
            # D-68 courier choice; the Lalamove API key (pk_test_) identifies, the secret signs.
            f"COURIER={_local_env('COURIER') or 'lalamove'}",
            f"LALAMOVE_API_KEY={_local_env('LALAMOVE_API_KEY')}",
            # D-67 GrabExpress sandbox: client id and pickup point are not secret.
            f"GRAB_CLIENT_ID={_local_env('GRAB_CLIENT_ID')}",
            f"PHARMACY_ADDRESS={_local_env('PHARMACY_ADDRESS')}",
            f"PHARMACY_LAT={_local_env('PHARMACY_LAT')}",
            f"PHARMACY_LNG={_local_env('PHARMACY_LNG')}",
            f"PHARMACY_PHONE={_local_env('PHARMACY_PHONE')}",
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
    # The keys never appear in the command or the service settings, only references.
    secrets = []
    if _secret_exists(GEMINI_SECRET):
        secrets.append(f"GEMINI_API_KEY={GEMINI_SECRET}:latest")
    else:
        print(
            "Note: no Gemini secret yet, so the live AI agent uses offline replies. "
            "Run: python tasks.py set-gemini-secret --yes"
        )
    if brevo:
        secrets.append(f"EMAIL_API_KEY={BREVO_SECRET}:latest")
    else:
        print(
            "Note: no Brevo secret yet, so live email and SMS are only logged. "
            "Run: python tasks.py set-brevo-secret --yes"
        )
    if stripe:
        secrets.append(f"STRIPE_SECRET_KEY={STRIPE_SECRET}:latest")
        if _secret_exists(STRIPE_WEBHOOK_SECRET):
            secrets.append(f"STRIPE_WEBHOOK_SECRET={STRIPE_WEBHOOK_SECRET}:latest")
    else:
        print(
            "Note: no Stripe secret yet, so payments use the simulated card form. "
            "Run: python tasks.py set-stripe-secrets --yes"
        )
    if _secret_exists(LALAMOVE_SECRET):
        secrets.append(f"LALAMOVE_API_SECRET={LALAMOVE_SECRET}:latest")
    else:
        print("Note: no Lalamove secret yet. Run: python tasks.py set-lalamove-secrets --yes")
    if _secret_exists(GRAB_SECRET):
        secrets.append(f"GRAB_CLIENT_SECRET={GRAB_SECRET}:latest")
        if _secret_exists(GRAB_WEBHOOK_SECRET):
            secrets.append(f"GRAB_WEBHOOK_SECRET={GRAB_WEBHOOK_SECRET}:latest")
    else:
        print("Note: no Grab secret (only needed with COURIER=grab).")
    if secrets:
        cmd += ["--set-secrets", ",".join(secrets)]
    confirm_cloud(
        "deploy FastAPI to Cloud Run (Cloud Build builds backend/Dockerfile)", [cmd]
    )
    # Ship only what FastAPI loads: selected calibrated models + JSON metadata.
    target = BACKEND / "ml_artifacts"
    if ML_ARTIFACTS.exists():
        for f in ML_ARTIFACTS.iterdir():
            if f.name.endswith("_model.joblib") or f.suffix == ".json":
                shutil.copy2(f, target / f.name)
    run(cmd)


# Text that only appears in main.dart.js when the plugin's web code is compiled in. A stale
# build cache once shipped a portal without flutter_secure_storage_web (every secure message
# failed with MissingPluginException), so the deploy now checks before uploading.
WEB_PLUGIN_MARKERS = {
    "flutter_secure_storage_web (D-42 message keys)": "FlutterSecureStorageWeb only works",
}


def build_staff_web(build: list[str]) -> None:
    # Flutter caches the generated web plugin list per build configuration and does not
    # always refresh it when plugins are added; clearing the cache forces a fresh one.
    shutil.rmtree(APP / ".dart_tool" / "flutter_build", ignore_errors=True)
    run(build, cwd=APP)
    js = (APP / "build" / "web" / "main.dart.js").read_text(encoding="utf-8", errors="ignore")
    missing = [name for name, marker in WEB_PLUGIN_MARKERS.items() if marker not in js]
    if missing:
        sys.exit(f"Staff portal build is missing web plugins: {', '.join(missing)}. Not deploying.")


def task_deploy_web() -> None:
    build = [
        exe("flutter"),
        "build",
        "web",
        "--release",
        "-t",
        "lib/main_staff.dart",
        "--dart-define-from-file=.env",
    ]
    deploy = [exe("firebase"), "deploy", "--only", "hosting", "--project", PROJECT_ID]
    confirm_cloud("build the staff portal and deploy Firebase Hosting", [build, deploy])
    build_staff_web(build)
    # Hosting can only serve files inside the firebase/ project directory.
    public = FIREBASE / "public"
    shutil.rmtree(public, ignore_errors=True)
    shutil.copytree(APP / "build" / "web", public)
    run(deploy, cwd=FIREBASE)


STORAGE_BUCKET = f"{PROJECT_ID}.firebasestorage.app"


def task_set_storage_cors() -> None:
    """D-52: browsers may only download Storage files from origins the bucket allows."""
    cmd = [
        exe("gcloud"),
        "storage",
        "buckets",
        "update",
        f"gs://{STORAGE_BUCKET}",
        f"--cors-file={FIREBASE / 'storage.cors.json'}",
        "--project",
        PROJECT_ID,
    ]
    confirm_cloud("allow the staff portal to download Storage files (CORS)", [cmd])
    run(cmd)


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
        [
            gcloud,
            "iam",
            "service-accounts",
            "describe",
            SCHEDULER_SA,
            "--project",
            PROJECT_ID,
        ]
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
                "Harvey Cloud Scheduler (OIDC caller)",
            ],
        )
    confirm_cloud(
        "create/update Cloud Scheduler jobs (and the caller service account if missing)",
        plans,
    )
    for p in plans:
        run(p)


def read_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, _, value = line.partition("=")
            values[key.strip()] = value.strip()
    return values


def task_firebase_config() -> None:
    """Generate android/app/src/<flavor>/google-services.json from templates + app/.env."""
    env_file = APP / ".env"
    if not env_file.exists():
        sys.exit(
            "app/.env missing. Copy app/.env.example to app/.env and fill in the keys."
        )
    values = read_env_file(env_file)
    key = values.get("FIREBASE_ANDROID_API_KEY", "")
    if not key:
        sys.exit("FIREBASE_ANDROID_API_KEY is empty in app/.env.")
    for flavor in ("patient", "family"):
        folder = APP / "android" / "app" / "src" / flavor
        text = (folder / "google-services.template.json").read_text(encoding="utf-8")
        (folder / "google-services.json").write_text(
            text.replace("${FIREBASE_ANDROID_API_KEY}", key), encoding="utf-8"
        )
    print("Generated google-services.json for patient and family flavors.")


def task_adb_reverse() -> None:
    """Physical phone over USB: forward FastAPI + emulator ports to this PC (docs/10 §3)."""
    sdk_adb = (
        Path(os.environ.get("LOCALAPPDATA", "")) / "Android" / "Sdk" / "platform-tools"
    )
    adb = shutil.which("adb") or str(sdk_adb / "adb.exe")
    run([adb, "devices"])
    for port in (8000, 9099, 8080, 9199):
        run([adb, "reverse", f"tcp:{port}", f"tcp:{port}"])


def _adb() -> str:
    sdk_adb = (
        Path(os.environ.get("LOCALAPPDATA", "")) / "Android" / "Sdk" / "platform-tools"
    )
    return shutil.which("adb") or str(sdk_adb / "adb.exe")


def task_phone_install() -> None:
    """Build + install + launch an app flavor on a USB phone without the debugger.

    Some phones (e.g. MTN/Transsion) obfuscate logcat, so `flutter run` never finds the
    VM service and the app waits on the splash screen. This path skips the debugger.
    Usage: python tasks.py phone-install [patient|family]
    """
    args = [a for a in sys.argv[2:] if a != "--yes"]
    flavor = args[0] if args else "patient"
    if flavor not in ("patient", "family"):
        sys.exit("flavor must be patient or family")
    install_dev_app(flavor)


def install_dev_app(flavor: str) -> None:
    """Debug build pointed at this PC (emulators + local API over adb reverse)."""
    task_firebase_config()
    task_adb_reverse()
    run(
        [
            exe("flutter"),
            "build",
            "apk",
            "--debug",
            "--flavor",
            flavor,
            "-t",
            f"lib/main_{flavor}.dart",
            "--dart-define=API_BASE_URL=http://localhost:8000",
            "--dart-define=USE_EMULATORS=true",
            "--dart-define=EMULATOR_HOST=localhost",
            "--dart-define-from-file=.env",
        ],
        cwd=APP,
    )
    apk = APP / "build" / "app" / "outputs" / "flutter-apk" / f"app-{flavor}-debug.apk"
    package = f"fyp.hypertension.{flavor}"
    run([_adb(), "install", "-r", str(apk)])
    run([_adb(), "shell", "am", "force-stop", package])
    run(
        [
            _adb(),
            "shell",
            "monkey",
            "-p",
            package,
            "-c",
            "android.intent.category.LAUNCHER",
            "1",
        ]
    )


def _port_open(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.5)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def _wait_for_port(
    port: int, name: str, proc: subprocess.Popen[bytes] | None, timeout: int
) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if _port_open(port):
            return
        if proc is not None and proc.poll() is not None:
            sys.exit(f"{name} stopped while starting (exit code {proc.returncode}).")
        time.sleep(1)
    sys.exit(f"{name} did not start within {timeout}s (port {port}).")


def _demo_accounts_present() -> bool:
    """True if the Auth emulator already has the seeded demo admin."""
    url = (
        f"http://localhost:9099/identitytoolkit.googleapis.com/v1/projects/{PROJECT_ID}"
        "/accounts:query"
    )
    req = urllib.request.Request(
        url,
        data=b"{}",
        headers={"Content-Type": "application/json", "Authorization": "Bearer owner"},
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as res:  # noqa: S310
            users = json.load(res).get("userInfo", [])
    except OSError:
        return False
    return any(u.get("email") == "admin@careflow.test" for u in users)


def _phone_connected() -> bool:
    code, out = capture([_adb(), "devices"])
    return code == 0 and any(line.endswith("\tdevice") for line in out.splitlines()[1:])


def task_dev() -> None:
    """One command for local development (double-click dev.cmd).

    Starts the emulators, seeds demo accounts if they are missing, starts FastAPI,
    installs the patient app on a plugged-in phone, then waits. Ctrl+C once stops
    everything and lets the emulators save their data. Add --no-phone to skip the phone.
    """
    flags = set(sys.argv[2:])
    started: list[tuple[str, subprocess.Popen[bytes]]] = []

    if _port_open(9099) and _port_open(8080):
        print("Emulators already running: reusing them.")
        emu = None
    elif _port_open(9099) or _port_open(8080):
        sys.exit(
            "Only part of the emulator suite is running (an orphan from an interrupted "
            "shutdown is holding port 8080 or 9099). Stop it in Task Manager (java.exe / "
            "node.exe) or restart the PC, then run dev again."
        )
    else:
        print("Starting Firebase emulators...", flush=True)
        emu = subprocess.Popen(emulator_command(), cwd=FIREBASE)  # noqa: S603
        started.append(("Emulators", emu))
    _wait_for_port(9099, "Auth emulator", emu, 180)
    _wait_for_port(8080, "Firestore emulator", emu, 180)

    if _demo_accounts_present():
        print("Demo accounts already loaded.")
    else:
        task_seed()

    if _port_open(8000):
        print("FastAPI already running on port 8000: reusing it.")
    else:
        print("Starting FastAPI...", flush=True)
        api = subprocess.Popen(  # noqa: S603
            [
                venv_python(),
                "-m",
                "uvicorn",
                "app.main:app",
                "--reload",
                "--host",
                "0.0.0.0",  # noqa: S104  (phones reach the PC through adb reverse)
                "--port",
                "8000",
                "--env-file",
                ".env",
            ],
            cwd=BACKEND,
        )
        started.append(("FastAPI", api))
        _wait_for_port(8000, "FastAPI", api, 60)

    if "--no-phone" in flags:
        print("Skipping the phone (--no-phone).")
    elif _phone_connected():
        print(
            "Phone detected: installing the patient app (local-dev build)...",
            flush=True,
        )
        install_dev_app("patient")
    else:
        print(
            "No phone connected: skipping app install. Plug one in and run phone-install."
        )

    print(
        "\n========================================================\n"
        " Harvey local stack is running\n"
        "   Emulator UI (accounts, data, reset links): http://localhost:4000\n"
        "   FastAPI docs:                              http://localhost:8000/api/docs\n"
        "   Live staff portal (cloud):                 https://hypertension-dd85f.web.app\n"
        " Press Ctrl+C ONCE to stop; wait for the emulators to finish saving.\n"
        "========================================================\n",
        flush=True,
    )
    try:
        while all(proc.poll() is None for _, proc in started):
            time.sleep(1)
        for name, proc in started:
            if proc.poll() is not None:
                print(f"{name} stopped (exit code {proc.returncode}).")
    except KeyboardInterrupt:
        print("\nStopping... the emulators are saving data, please wait.", flush=True)
    finally:
        # Ctrl+C reaches every process in this console, so the emulators export on
        # their own; give them time before forcing anything to close.
        for name, proc in reversed(started):
            try:
                proc.wait(timeout=90 if name == "Emulators" else 10)
            except (subprocess.TimeoutExpired, KeyboardInterrupt):
                proc.terminate()
        print("Stopped.")


def task_phone_live() -> None:
    """Build the release apps (live cloud) and install the Harvey app (D-63: patients
    and family members use the same app)."""
    if not _phone_connected():
        sys.exit("No phone connected. Plug it in (USB debugging on) and try again.")
    task_build_apk()
    out = APP / "build" / "app" / "outputs" / "flutter-apk"
    run([_adb(), "install", "-r", str(out / "app-patient-release.apk")])
    run(
        [
            _adb(),
            "shell",
            "monkey",
            "-p",
            "fyp.hypertension.patient",
            "-c",
            "android.intent.category.LAUNCHER",
            "1",
        ]
    )
    print("Live-cloud Harvey app installed. It no longer needs this PC.")


def task_bootstrap_admin() -> None:
    """One-time: create the first admin in the LIVE project (firebase/seed/bootstrap_admin.py)."""
    args = [a for a in sys.argv[2:] if a != "--yes"]
    if len(args) != 2:
        sys.exit(
            'Usage: python tasks.py bootstrap-admin you@example.com "Your Name" --yes'
        )
    email, name = args
    cmd = [venv_python(), str(FIREBASE / "seed" / "bootstrap_admin.py"), email, name]
    confirm_cloud(
        f"create the first admin account ({email}) in the LIVE project", [cmd]
    )
    live_env = {
        k: v
        for k, v in os.environ.items()
        if k not in {"FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST"}
    }
    print(f"\n> {' '.join(cmd)}", flush=True)
    result = subprocess.run(cmd, cwd=ROOT, env=live_env, check=False)  # noqa: S603
    sys.exit(result.returncode)


def task_seed_catalog_live() -> None:
    """Load symptom_catalog reference data into the LIVE Firestore (idempotent, FR-14.3)."""
    cmd = [venv_python(), str(FIREBASE / "seed" / "catalog_live.py")]
    confirm_cloud(
        "write symptom_catalog and medication_catalog (+ demo stock, create-only) to the LIVE "
        "project",
        [cmd],
    )
    live_env = {
        k: v
        for k, v in os.environ.items()
        if k not in {"FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST"}
    }
    print(f"\n> {' '.join(cmd)}", flush=True)
    result = subprocess.run(cmd, cwd=FIREBASE / "seed", env=live_env, check=False)
    if result.returncode != 0:
        sys.exit(result.returncode)


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
            "--dart-define-from-file=.env",
        ]
        for flavor in ("patient", "family")
    ]
    task_firebase_config()
    for c in cmds:
        run(c, cwd=APP)


def task_deploy_all() -> None:
    """Rules first (new collections need them), then backend, then the portal and jobs."""
    global ASSUME_YES
    steps = [
        ("Firestore rules + indexes, Storage rules", task_deploy_rules),
        ("Storage CORS for the staff portal", task_set_storage_cors),
        ("Reference data: symptom catalog", task_seed_catalog_live),
        ("FastAPI backend on Cloud Run", task_deploy_backend),
        ("Staff portal on Firebase Hosting", task_deploy_web),
        (
            "Cloud Scheduler jobs (only missing ones are created)",
            task_create_scheduler_jobs,
        ),
    ]
    print(f"CLOUD ACTION: deploy everything to the LIVE project {PROJECT_ID}:")
    for i, (label, _) in enumerate(steps, 1):
        print(f"   {i}. {label}")
    if not ASSUME_YES:
        try:
            answer = (
                input("\nType yes to deploy (anything else cancels): ").strip().lower()
            )
        except EOFError:  # no keyboard (e.g. piped): never deploy by accident
            answer = ""
        if answer != "yes":
            sys.exit("Cancelled. Nothing was deployed.")
        ASSUME_YES = True
    started = time.monotonic()
    for i, (label, step) in enumerate(steps, 1):
        print(f"\n===== [{i}/{len(steps)}] {label} =====", flush=True)
        step()  # run() exits on the first failure, so later steps never run half-deployed
    minutes = (time.monotonic() - started) / 60
    print(f"\nAll {len(steps)} deploy steps finished in {minutes:.1f} min.")
    print("Live portal: https://hypertension-dd85f.web.app")
    print("Phone app: run phone-live.cmd if the app code changed.")


TASKS = {
    "deploy-all": task_deploy_all,
    "emulators": task_emulators,
    "seed": task_seed,
    "api": task_api,
    "test": task_test,
    "lint": task_lint,
    "deploy-backend": task_deploy_backend,
    "deploy-web": task_deploy_web,
    "deploy-rules": task_deploy_rules,
    "set-storage-cors": task_set_storage_cors,
    "create-scheduler-jobs": task_create_scheduler_jobs,
    "set-gemini-secret": task_set_gemini_secret,
    "set-brevo-secret": task_set_brevo_secret,
    "set-stripe-secrets": task_set_stripe_secrets,
    "set-grab-secrets": task_set_grab_secrets,
    "set-lalamove-secrets": task_set_lalamove_secrets,
    "seed-catalog-live": task_seed_catalog_live,
    "build-apk": task_build_apk,
    "backend-url": task_backend_url,
    "adb-reverse": task_adb_reverse,
    "phone-install": task_phone_install,
    "dev": task_dev,
    "phone-live": task_phone_live,
    "bootstrap-admin": task_bootstrap_admin,
    "firebase-config": task_firebase_config,
}


def main() -> None:
    args = [a for a in sys.argv[1:] if a != "--yes"]
    if not args or args[0] not in TASKS:
        print(__doc__)
        sys.exit(0 if not args else 1)
    TASKS[args[0]]()


if __name__ == "__main__":
    main()
