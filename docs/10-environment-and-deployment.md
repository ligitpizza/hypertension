# 10 — Environment, Cloud Setup & Deployment

Covers how Flutter and FastAPI/ML work together, local development in VS Code, the Firebase **Blaze** plan setup, and deployment. Decided before development starts (D-19 to D-22).

## 1. How the pieces talk

Flutter (Dart) and FastAPI (Python) are **separate processes connected over HTTPS/JSON**. scikit-learn and XGBoost cannot run in Dart, so all ML inference lives in FastAPI.

```
Flutter app ──HTTP/JSON──▶ FastAPI ──▶ ML models (.joblib, loaded once at startup)
     │                         └──▶ Firebase Admin SDK (Firestore, Auth, Storage, FCM)
     └── Firestore SDK (real-time listeners, direct reads)
```

- `ml/`: offline training (Jupyter notebooks in VS Code). Outputs go to `ml/artifacts/`.
- `backend/app/ml/`: loads the artefacts at startup and serves `/api/v1/risk-score`.
- Flutter only ever calls the endpoint and reads JSON.

## 2. Cloud plan: Firebase Blaze (D-19)

The project uses **one Firebase project = one Google Cloud project** on the **Blaze (pay-as-you-go) plan**. This matches Ch4 §4.4.2 exactly:

| Need | Service | Requires Blaze? |
|---|---|---|
| FastAPI + ML | Cloud Run | Yes |
| Health record uploads (M6) | Cloud Storage for Firebase | Yes (since Feb 2026) |
| Background jobs | Cloud Scheduler → Cloud Run `/internal/jobs/*` | Yes |
| Staff web portal | Firebase Hosting + `/api/**` rewrite to Cloud Run | Rewrite to Cloud Run needs Blaze |
| Auth, Firestore, FCM | Firebase | No (free quotas still apply on Blaze) |

### Cost controls (mandatory)

- Ping upgrades to Blaze and links billing **before Increment 0**. The $300 / 90-day trial credit is used if eligible. Claude Code never handles billing or card details.
- Set a **budget alert** (≈ RM20 / USD 5, alerts at 50/90/100%) immediately. Alerts don't cap spending.
- Cloud Run: `--min-instances=0 --max-instances=2`, memory 1 GiB (enough for 10 models; adjust after measuring), CPU 1, concurrency 20.
- Cloud Scheduler: keep the number of jobs small. Combine related tasks into one daily job and one monthly job where possible.
- Hosting: keep `"hosting.predeploy"` builds small and delete old releases (retain ~5) to stay inside the free storage.
- Never enable paid extras (Firestore backups/PITR, Cloud Armor, larger instances) without asking Ping.

### Region (D-20)

**`asia-southeast1` (Singapore)** for Firestore, Storage, Cloud Run, Cloud Scheduler and Artifact Registry. Firestore and Storage regions are **permanent**. Keeping everything in one region keeps latency low for Malaysian users (NFR-1.1 < 2 s, NFR-1.2 < 3 s).

### One-time setup (Ping does this before Increment 0) — status in `00-getting-started.md` §1

1. Create the Firebase project with a personal Google account, then upgrade to Blaze and set the budget alert.
2. Enable Authentication (Email/Password), Firestore (production mode, asia-southeast1) and Storage (asia-southeast1).
3. Enable these Google Cloud APIs: Cloud Run Admin, Cloud Build, Artifact Registry, Cloud Scheduler, Secret Manager.
4. Install the Firebase CLI and gcloud CLI. Run `firebase login`, `gcloud auth login`, then `gcloud config set project <PROJECT_ID>`.
5. Give Claude Code the **project ID** and region. Secrets go into `.env` locally and Secret Manager in the cloud, never into chat or git.

## 3. Local development (VS Code)

Day-to-day work runs **locally and free** on the Firebase Emulator Suite. The cloud is used for the walking-skeleton deploy and the end-of-increment deploys (§4).

**Extensions:** Flutter, Dart, Python, Pylance, Ruff, Jupyter.

**Processes (one VS Code compound launch config starts all of them):**
1. `firebase emulators:start --import=./firebase/seed-data --export-on-exit` (Auth, Firestore, Storage, UI)
2. `uvicorn app.main:app --reload --host 0.0.0.0 --port 8000` in `backend/.venv`
3. Flutter: run the `patient` / `family` flavor on the Android emulator, or `main_staff.dart` on Chrome

**API base URL** comes from a config value (`--dart-define=API_BASE_URL=...`), never hard-coded:

| Running on | Base URL | Emulator host |
|---|---|---|
| Android emulator | `http://10.0.2.2:8000` | `10.0.2.2` |
| Physical Android (USB) | `adb reverse tcp:8000 tcp:8000` (and the emulator ports) → `http://localhost:8000` | `localhost` |
| Chrome (staff portal) | `http://localhost:8000` | `localhost` |
| Production | `https://<project>.web.app/api` (staff) / Cloud Run URL (mobile) | — |

**Required local-dev config:**
- FastAPI **CORS** in dev only, allowing `http://localhost:*` (Flutter Web picks a random port). Production needs no CORS because Hosting rewrites `/api/**` to the same origin.
- Android **cleartext HTTP** allowed in a `debug`-only `network_security_config.xml` for `10.0.2.2` / `localhost`. Release builds are HTTPS only (NFR-2.4).
- Flutter: when `USE_EMULATORS=true`, call `useAuthEmulator`, `useFirestoreEmulator` and `useStorageEmulator`.
- Backend: Firebase Admin SDK picks up `FIRESTORE_EMULATOR_HOST`, `FIREBASE_AUTH_EMULATOR_HOST` and `FIREBASE_STORAGE_EMULATOR_HOST` from `.env`.
- Third-party adapters use **fake** implementations locally (`INTEGRATIONS_MODE=fake`). Stripe test mode can use the Stripe CLI (`stripe listen --forward-to localhost:8000/api/v1/webhooks/stripe`).
- Scheduled jobs locally: call `/internal/jobs/<job>` manually or from tests.

## 4. Deployment cadence (D-21)

- **Walking-skeleton deploy, end of Increment 0.** Deploy FastAPI (health endpoint + auth check) to Cloud Run, deploy the empty staff portal to Hosting with the `/api/**` rewrite, deploy Firestore/Storage rules + indexes, and create one test scheduler job. This proves the deployment pipeline works before any feature depends on it.
- **End of every increment.** Redeploy everything and smoke-test on the live URL and a real Android device. Record the live versions in `IMPLEMENTATION_LOG.md`.
- **Phase 5.** Final deploy, then performance checks for NFR-1.1 and NFR-1.2 against the live environment.

### Deploy artefacts Claude Code must create (Increment 0)

- `backend/Dockerfile` (python slim, non-root user, copies `ml/artifacts/` in, `uvicorn` on `$PORT`)
- `scripts/deploy_backend.sh` (`gcloud run deploy careflow-api --source backend --region asia-southeast1 --min-instances 0 --max-instances 2 --memory 1Gi --set-secrets ...`)
- `firebase/firebase.json`: hosting `public: app/build/web`, rewrite `{"source": "/api/**", "run": {"serviceId": "careflow-api", "region": "asia-southeast1"}}`, plus rules and indexes paths
- `scripts/deploy_web.sh` (`flutter build web -t lib/main_staff.dart` → `firebase deploy --only hosting`)
- `scripts/deploy_rules.sh` (`firebase deploy --only firestore:rules,firestore:indexes,storage`)
- `scripts/create_scheduler_jobs.sh` (idempotent; OIDC-authenticated calls to `/internal/jobs/*`)
- Release APK build commands per flavor
- `.env.example` listing every variable with no real values

## 5. Third-party services (outside Blaze)

| Service | Account | Mode |
|---|---|---|
| Gemini Flash | Google AI Studio API key (in Secret Manager) | Free tier |
| Stripe | Test-mode keys + webhook secret | Sandbox only (scope) |
| Grab | Sandbox credentials if obtainable, otherwise fake simulator (D-11) | Sandbox / fake |
| Email | See D-22. SendGrid's free tier is reportedly discontinued; verify before use | Free tier provider behind the email adapter |
| Twilio SMS | Trial account (verified numbers only) | Trial |
| Google Maps | API key restricted to Android package + Hosting domain | Free monthly credit |
