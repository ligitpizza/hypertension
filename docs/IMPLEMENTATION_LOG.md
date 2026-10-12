# Implementation Log

Raw notes for FYP Chapter 5. Append one entry per completed module.

## Template

### YYYY-MM-DD — Increment N — Module X: <name>
- FRs implemented: FR-x.x, …
- Use-case exception flows handled: UCx.x E1, …
- Tests: N unit, N widget, N rules, N integration (all passing)
- Deviations / additions vs Chapter 4: (new fields/collections, changed flows — with reason)
- Known limitations:

---

### 2026-10-12 — Increment 0 — Project setup (walking skeleton)
- Scope: monorepo skeleton (app/, backend/, firebase/, tasks.py, .vscode/), Flutter app with
  `patient`/`family` flavors + `main_staff.dart` web entrypoint, Firebase apps registered via
  flutterfire, emulator wiring, FastAPI skeleton (auth dependency, audit logger, health,
  `/internal/jobs/heartbeat`), shared enums + `docs/fixtures/enums.json`, Firestore/Storage
  rules baseline + composite indexes, emulator seed (symptom_catalog + 1 demo account per role),
  deploy artefacts (Dockerfile, tasks.py deploy-*), commit-msg hook active.
- FRs touched (foundations only): FR-1.3 (role claim check + `require_roles`), FR-1.5 (audit
  logger), NFR-2.2 (deny-by-default rules), NFR-2.4 (debug-only cleartext), NFR-4.2 (offline
  persistence), NFR-3.1 (48 dp targets in theme).
- Tests: 23 Dart (20 unit enum-parity, 3 widget: loading/data/error), 42 pytest, 28 rules
  (Firestore + Storage, every role) — all passing. `flutter analyze`, ruff, ruff format, mypy
  --strict clean.
- Local verification: emulators + seed run; emulator sign-in as demo doctor -> FastAPI
  `/api/v1/health/auth` returns role `doctor`; heartbeat job writes `audit_logs` in the emulator.
  Staff portal web release build compiles.
- Deployed (walking skeleton, 2026-10-12):
  - Firestore rules + indexes, Storage rules.
  - Cloud Run `careflow-api` revision `careflow-api-00002-c5t` (asia-southeast1, min 0 / max 2,
    1 GiB): https://careflow-api-247793990377.asia-southeast1.run.app — `/api/v1/health` 200,
    `/api/v1/health/auth` 401 without token, `/internal/jobs/heartbeat` 401 without OIDC token.
  - Firebase Hosting (staff portal shell): https://hypertension-dd85f.web.app —
    `/api/v1/health` returns `ok` through the `/api/**` rewrite (exit test).
  - Cloud Scheduler job `careflow-heartbeat` (daily 03:00 Asia/Kuala_Lumpur, OIDC as
    `careflow-scheduler@…`, audience `careflow-internal-jobs`).
  - Setup notes: Cloud Build on this project runs as the Compute default service account; the
    Cloud Scheduler API had to be enabled (was not on at project creation). Hosting serves
    `firebase/public/` (copied from `app/build/web`).
- Deviations / additions vs Chapter 4:
  - D-23 Android application IDs `fyp.hypertension.patient` / `.family`; Dart package `hypertension`.
  - D-24 `tasks.py` replaces `make` and `.sh` scripts (make not available on Windows).
  - D-12 minSdk raised 23 -> 24 (Flutter 3.44 minimum).
  - Risk level enum stored lowercase (`low|moderate|high|critical`) for consistency with the other
    snake/lower-case enums; Ch4 only names the levels.
  - `symptom_catalog` document IDs are stable slugs (e.g. `chest_pain`) instead of auto IDs, so
    seeding is idempotent and fixtures can reference them.
  - Scheduler OIDC audience is a fixed string (`careflow-internal-jobs`) verified by FastAPI;
    `/internal/jobs/*` is not under `/api`, so Hosting never exposes it.
  - Firebase emulators require JDK 21 (installed Temurin 21).
- Android exit test (2026-10-12): patient flavor debug build on a physical phone (MTN NX1,
  Android 16 / API 36) over USB with `adb reverse` (the documented alternative to the
  `10.0.2.2` emulator path, docs/10 §3) shows "API status: ok" from local FastAPI. PASSED.
  - Build fixes needed on Windows: enable `buildFeatures.resValues` (per-flavor app name) and
    `kotlin.incremental=false` (project on D:, pub cache on C:).
- Known limitations: no Android emulator (AVD) configured on the dev machine; the `10.0.2.2`
  path is configured but was verified with a physical phone instead.
