# 00 — Getting Started (setup status + repo layout)

Read this first. It records what Ping has already set up and how the repository is organised, so you can start Increment 0 without re-asking.

## 1. Cloud setup — already DONE by Ping

| Item | Value / status |
|---|---|
| Firebase / Google Cloud project name | Hypertension |
| **Project ID** | **`hypertension-dd85f`** |
| Plan | **Blaze** (pay-as-you-go), linked to "My Billing Account" |
| Free trial | RM1,224.75 (~USD 300) credit, 90 days from 12 Oct 2026 (expires ~10 Jan 2027) |
| Budget alert | RM25, scoped to this project |
| Region (all regional services) | **`asia-southeast1`** (Singapore) |
| Cloud Firestore | Standard edition, database ID **`(default)`**, asia-southeast1, production mode (locked rules) |
| Cloud Storage | Default bucket **`gs://hypertension-dd85f.firebasestorage.app`**, asia-southeast1, Standard class, production rules |
| Firebase Authentication | Email/Password provider enabled |
| Google Cloud APIs enabled | Cloud Run Admin, Cloud Build, Artifact Registry, Cloud Scheduler, Secret Manager |

**Not done yet (Increment 0 tasks, or Ping does them when asked):**
- Firebase CLI + Google Cloud CLI installed and logged in (`firebase login`, `gcloud auth login`, `gcloud config set project hypertension-dd85f`). If a CLI command fails because it's missing or not logged in, stop and ask Ping to do it. Never handle credentials yourself.
- Android apps (patient + family flavors) and the web app registered in Firebase. Use `flutterfire configure` once the Flutter app exists.
- Cloud Run service, Hosting site, Scheduler jobs, Secret Manager secrets: none created yet.

**Rules:**
- Never change billing, budgets, plan, or regions.
- Never enable additional paid features (Firestore backups/PITR, Enterprise edition, extra databases, larger Cloud Run instances) without asking.
- Never create a second Firestore database. Always use `(default)`.

## 2. Repository layout — one monorepo for Flutter + Python

The repo root directory is **`hypertension/`**. Ping opens this folder in VS Code. Flutter (Dart) and the FastAPI/ML backend (Python) **coexist in this one repo**, in separate top-level folders.

```
hypertension/                 ← repo root; open this folder in VS Code
├── CLAUDE.md                 ← your instructions
├── docs/                     ← spec (00–10), figures, source chapters, IMPLEMENTATION_LOG.md
├── .claude/settings.json     ← commit attribution disabled
├── scripts/
│   └── git-hooks/commit-msg  ← strips any AI attribution trailer
├── .vscode/                  ← launch.json (compound F5), settings.json, extensions.json  [create in Inc 0]
├── app/                      ← Flutter project (Dart)                                      [create in Inc 0]
├── backend/                  ← FastAPI (Python 3.11+), own virtualenv backend/.venv          [create in Inc 0]
├── ml/                       ← model training (Python, Jupyter notebooks), artifacts/        [create in Inc 0/2]
└── firebase/                 ← firebase.json, .firebaserc, rules, indexes, seed            [create in Inc 0]
```

- There is **no existing Flutter code**. Ping's earlier `flutter create` starter is discarded, so create `app/` fresh.
- `app/` and `backend/` are independent projects. Flutter never imports Python. They communicate only over HTTP/JSON (`10-environment-and-deployment.md` §1).
- Python virtualenvs live inside their folders (`backend/.venv`, `ml/.venv`) and are git-ignored.
- The internal app name stays **CareFlow** (titles, Cloud Run service `careflow-api`, etc.). Only the repo folder is named `hypertension`.

### Creating the Flutter app (Increment 0)

```bash
cd hypertension
flutter create --platforms android,web --org my.edu.tarumt --project-name careflow app
```

- `--org my.edu.tarumt` → Android package base `my.edu.tarumt.careflow`. **Confirm the org with Ping before running**; it's permanent once registered in Firebase.
- Android product flavors: `patient` (applicationId `my.edu.tarumt.careflow.patient`) and `family` (`my.edu.tarumt.careflow.family`).
- Entrypoints: `lib/main_patient.dart`, `lib/main_family.dart`, `lib/main_staff.dart` (web).
- No iOS / macOS / Windows / Linux folders (Android + web only, D-13).
- Then `flutterfire configure --project=hypertension-dd85f` for the two Android flavors and the web app.

## 3. VS Code setup

**Extensions** (recommend them in `.vscode/extensions.json`): Dart, Flutter, Python, Pylance, Ruff, Jupyter.

**Python interpreter:** after `backend/.venv` exists, Ping selects it via `Ctrl+Shift+P → Python: Select Interpreter`. Set the default in `.vscode/settings.json` (`"python.defaultInterpreterPath": "backend/.venv/..."`, with the correct path for Windows `Scripts/python.exe`).

**F5 compound launch** (`.vscode/launch.json`): one configuration that starts
1. Firebase emulators (Auth, Firestore, Storage, UI) with seed import/export
2. FastAPI: `uvicorn app.main:app --reload --host 0.0.0.0 --port 8000` from `backend/` using `backend/.venv`
3. Flutter patient app on the Android emulator (`--flavor patient -t lib/main_patient.dart --dart-define=API_BASE_URL=http://10.0.2.2:8000 --dart-define=USE_EMULATORS=true`)

Plus separate configs for the family app (`--flavor family`) and the staff portal on Chrome (`-t lib/main_staff.dart -d chrome --dart-define=API_BASE_URL=http://localhost:8000`).

**OS:** Ping is most likely on **Windows**; confirm at the start. Write scripts so they work there: provide PowerShell or cross-platform alternatives for any `.sh` scripts (or use Python scripts / `make` alternatives such as a `tasks.py`), and use Windows venv paths (`.venv\Scripts\activate`).

## 4. Kick-off prompt (Ping pastes this into Claude Code)

> Read CLAUDE.md and all of docs/, starting with docs/00-getting-started.md. The cloud setup in section 1 is done. Before writing code: (1) confirm the Android org/package name with me, and (2) list any open questions from docs/09 you need answered for Increment 0. Then start Increment 0 following docs/08-build-plan.md.

## 5. Commit rules reminder

Before the first commit, make sure the hook is active: `git config core.hooksPath scripts/git-hooks`. Commit messages describe the change only, with no AI attribution of any kind (see CLAUDE.md).
