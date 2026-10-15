"""Application settings, read from environment variables / backend/.env (docs/10 §3)."""

from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_env: Literal["dev", "prod"] = "prod"
    app_version: str = "0.1.0"
    firebase_project_id: str = "hypertension-dd85f"

    # Dev only: Flutter Web picks a random localhost port, so allow any of them.
    # Production needs no CORS because Hosting rewrites /api/** to the same origin.
    cors_origin_regex: str = r"^http://(localhost|127\.0\.0\.1)(:\d+)?$"

    # Third-party adapters: "fake" locally, "real" in the cloud (docs/05).
    integrations_mode: Literal["fake", "real"] = "fake"

    # Trained models (ml/artifacts locally; copied into the image as /srv/ml_artifacts).
    ml_artifacts_dir: Path = Path(__file__).resolve().parents[3] / "ml" / "artifacts"

    # Email (D-22: Brevo). Used for staff setup links (UC1.5) and later reminders.
    email_api_key: str = ""
    email_from: str = ""
    email_from_name: str = "CareFlow"

    # Push notifications (D-33): false logs pushes instead of sending them through FCM.
    fcm_enabled: bool = False

    # AI Health Agent (FR-14.1, docs/06 §G). Empty key = offline fake replies.
    gemini_api_key: str = ""
    gemini_model: str = "gemini-3.1-flash-lite"
    gemini_timeout_seconds: float = 12.0
    # Per-patient agent requests per minute (protects the Gemini quota).
    agent_rate_per_minute: int = 10

    # Unauthenticated failed-login reporting (D-27): max reports per client IP per minute.
    failed_login_rate_per_minute: int = 10

    # /internal/jobs/* auth (D-08). "oidc" verifies the Cloud Scheduler OIDC token;
    # "none" is for local development and tests only.
    internal_jobs_auth: Literal["oidc", "none"] = "oidc"
    # Expected OIDC audience (the Cloud Run service URL) and caller service account.
    jobs_oidc_audience: str = ""
    jobs_service_account: str = ""

    # Testing aid (D-57): patients may book any time, even a past one, so the doctor's
    # Complete / No-show and the reminders can be tried without waiting. Off for real use.
    dev_appointment_times: bool = False

    @property
    def is_dev(self) -> bool:
        return self.app_env == "dev"


@lru_cache
def get_settings() -> Settings:
    return Settings()
