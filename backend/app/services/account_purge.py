"""D-46: purge accounts whose deletion was requested more than DELETION_GRACE ago.

Runs inside the existing daily `deterioration` Cloud Scheduler call (no new job). A support
or admin reactivation clears `deletionRequestedAt`, so those accounts are never picked up.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

from fastapi import Depends

from app.core.audit import SYSTEM_SCHEDULER_USER, AuditLogger, get_audit_logger
from app.core.enums import Collection
from app.services.identity import IdentityProvider, get_identity_provider
from app.services.settings import DELETION_GRACE, SettingsRepository, get_settings_repository

log = logging.getLogger("careflow.purge")


@dataclass
class AccountPurgeJob:
    repo: SettingsRepository
    identity: IdentityProvider
    audit: AuditLogger

    def run(self, now: datetime | None = None) -> dict[str, Any]:
        now = now or datetime.now(UTC)
        purged = 0
        for uid in self.repo.due_deletions(now - DELETION_GRACE):
            user = self.repo.user(uid) or {}
            if user.get("isActive") is not False:
                continue  # reactivated but the field was left behind: keep the account
            try:
                removed = self.repo.purge(uid)
                self.identity.delete_user(uid)
            except Exception:
                log.exception("Purge of %s failed; retried on the next daily run", uid)
                continue
            self.audit.log(
                user_id=SYSTEM_SCHEDULER_USER,
                action="DELETE_ACCOUNT",
                details=f"Account and {removed} patient-owned records deleted (UC12.4).",
                target_type=Collection.USERS.value,
                target_id=uid,
            )
            purged += 1
        return {"accountsPurged": purged}


def get_account_purge_job(
    repo: SettingsRepository = Depends(get_settings_repository),
    identity: IdentityProvider = Depends(get_identity_provider),
    audit: AuditLogger = Depends(get_audit_logger),
) -> AccountPurgeJob:
    return AccountPurgeJob(repo, identity, audit)
