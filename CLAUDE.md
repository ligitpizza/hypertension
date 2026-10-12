# CareFlow — Hypertension Care Management Platform

Final Year Project (BMCS3403, TAR UMT) by Woo Yee Ping. Solo academic project; you are implementing it from a finished design (FYP report Chapters 1–4). Chapter 5 (Implementation) will be written from what you build, so **the code must match the report's design**.

## Read first, in this order

| File | What it is |
|---|---|
| `docs/00-getting-started.md` | **Start here.** Cloud setup already done (project `hypertension-dd85f`), repo layout (Flutter + Python in one repo), Flutter create command, VS Code setup, kick-off steps |
| `docs/01-project-overview.md` | Problem, roles, objectives (incl. **AUC ≥ 0.80**), scope / out of scope, stack |
| `docs/02-requirements.md` | **52 FRs + 15 NFRs** (verbatim) with use-case and increment traceability |
| `docs/03-use-cases.md` | 67 use cases: triggers, basic flows, alternative and exception flows (behavioural spec) |
| `docs/04-data-model.md` | Firestore schema (20 collections), indexes, Security Rules, deletion cascade |
| `docs/05-architecture.md` | Deployment, monorepo layout, read/write split, routes, API endpoints, notifications, integrations |
| `docs/06-algorithms-and-flows.md` | Risk prediction, PPG, adherence, triage rules, BP classifier, escalation, AI agent, E2E messaging, recurring orders |
| `docs/07-ui-screens.md` | 41 mockups + descriptions, mapped to routes; known mockup deviations |
| `docs/08-build-plan.md` | Increments 0–3 + Phase 5, Definition of Done |
| `docs/09-decisions-and-open-questions.md` | Source conflicts and the decisions taken; **open questions to ask Ping** |
| `docs/10-environment-and-deployment.md` | Flutter ↔ FastAPI wiring, VS Code local dev (emulators, `10.0.2.2`, CORS), **Blaze** cloud setup, region, cost limits, deploy scripts and cadence |
| `docs/figures/` | Use-case and activity diagrams (Ch3); sequence diagrams, sitemap, class diagram, ERD, package, deployment, UI mockups (Ch4) |
| `docs/source/` | Raw chapter text + the original planning md. Only consult these if the docs above are ambiguous |

**Authority order when sources disagree:** Ch4 > Ch3 > Ch1 > `docs/source/hypertension_app_reference.md`. Never silently invent schema or behaviour. If something isn't specified, pick the simplest option consistent with the docs, then log it in `docs/IMPLEMENTATION_LOG.md` under "Deviations / additions".

## Stack (fixed — don't substitute)

- Flutter / Dart, with one codebase and three entrypoints: `main_patient.dart` (Android), `main_family.dart` (Android), `main_staff.dart` (Flutter Web).
- Riverpod, go_router, get_it, dio + retrofit, fl_chart, camera, google_maps_flutter, geolocator, flutter_stripe, firebase_messaging, flutter_local_notifications.
- Backend: FastAPI (Python 3.11+) on Cloud Run, Firebase Admin SDK, Pydantic v2.
- Firebase: Auth (role in custom claims), Cloud Firestore, Storage, FCM, Hosting (rewrites `/api/**` → Cloud Run).
- ML: scikit-learn Random Forest + XGBoost, 5 complications, artefacts loaded at FastAPI startup.
- Integrations: Gemini Flash (via backend only), Stripe **test mode**, Grab **sandbox or fake**, SendGrid, Twilio, Google Maps. Each sits behind an adapter interface with a fake implementation.
- Firebase **Blaze** plan, region **asia-southeast1** for everything regional. Cloud Run `max-instances=2`. Never enable other paid features without asking.
- Android only. No iOS config.

## How to work

1. Follow `docs/08-build-plan.md` strictly. Finish and test one increment before starting the next. Inside an increment, do one module at a time.
2. Before building a module, read its FRs, use cases, sequence diagram image, and UI mockups.
3. Meet the Definition of Done in `08-build-plan.md` for every module, including tests that cite FR/UC IDs, rules tests, and the `IMPLEMENTATION_LOG.md` entry.
4. Develop and test on the Firebase Emulator Suite + local uvicorn. Deploy at the end of Increment 0 (walking skeleton) and after every increment (`10-…md` §4). Ping handles billing; you never touch billing or card details. Never touch production data. Never commit secrets: use `.env` + `.env.example`.
5. Collection names, field names and enum values must match `docs/04-data-model.md` exactly. If you add a collection or field, it must be listed in `09-decisions-and-open-questions.md` first.
6. Ask Ping before implementing anything listed under "Open questions" in `09-…md`.
7. Health-safety copy: show the AI agent and the symptom checker with a "not a substitute for a doctor" disclaimer. The emergency number is **999**. Label PPG heart rate as an estimate.
8. Keep changes small and reviewable. Run `flutter analyze`, `flutter test`, `ruff`, `mypy` and `pytest` before each commit.

## Git commit rules — MANDATORY (academic integrity)

This is assessed academic work. AI attribution in the git history could create an academic integrity problem for the author.

- **Never** add `Co-Authored-By:`, `Co-authored-by:`, `Claude-Session:`, "Generated with Claude Code", or any other AI attribution, trailer, footer, or emoji tag to commit messages or PR descriptions.
- Never identify yourself as an author or co-author.
- A commit message contains **only** a description of the changes. Use Conventional Commits, e.g.:
  ```
  feat(vitals): log BP reading with plausible-range validation

  Implements FR-3.1 and UC3.1 E1. Adds BPClassifier with unit tests.
  ```
- This applies to every commit and PR in this repo unless Ping explicitly says otherwise.
- `.claude/settings.json` disables attribution, and `scripts/git-hooks/commit-msg` strips any trailer that slips through. Activate the hook once with `git config core.hooksPath scripts/git-hooks`.
