"""POST /risk-score/{patientId}: manual re-score, e.g. after a health-profile edit
(UC12.2 -> UC9.1). The patient may re-score themselves; admins may re-score anyone."""

from typing import Any

from fastapi import APIRouter, Depends, status

from app.core.audit import AuditLogger, get_audit_logger
from app.core.auth import CurrentUser, require_roles
from app.core.enums import Collection, UserRole
from app.core.errors import ApiError
from app.ml.risk_model import RiskModel, get_risk_model
from app.services.risk import (
    NotEnoughReadingsError,
    RiskDataRepository,
    generate_risk_score,
    get_risk_data_repository,
)

router = APIRouter(prefix="/risk-score", tags=["risk"])


@router.post("/{patient_id}", status_code=status.HTTP_201_CREATED)
def rescore(
    patient_id: str,
    user: CurrentUser = Depends(require_roles(UserRole.PATIENT, UserRole.ADMIN)),
    repo: RiskDataRepository = Depends(get_risk_data_repository),
    model: RiskModel | None = Depends(get_risk_model),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    if user.role is UserRole.PATIENT and user.uid != patient_id:
        raise ApiError("FORBIDDEN", "You can only re-score yourself.", status.HTTP_403_FORBIDDEN)
    if model is None:
        raise ApiError(
            "MODEL_UNAVAILABLE",
            "Risk models are not available.",
            status.HTTP_503_SERVICE_UNAVAILABLE,
        )
    try:
        result = generate_risk_score(patient_id, repo, model)
    except NotEnoughReadingsError as exc:
        raise ApiError("NOT_ENOUGH_READINGS", str(exc), status.HTTP_409_CONFLICT) from exc
    audit.log(
        user_id=user.uid,
        action="GENERATE_RISK_SCORE",
        details=f"Manual re-score; overall {result.prediction.overall_level.value}.",
        target_type=Collection.RISK_SCORES.value,
        target_id=result.score_id,
    )
    return result.to_response()
