"""Protected production-readiness and pipeline monitoring endpoints."""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from services.api_auth_service import require_owner, require_user_id
from services.operations_detail_service import operations_detail
from services.pipeline_run_service import recent_pipeline_runs, summarize_pipeline_health
from services.provider_availability_monitor_service import provider_availability_snapshot
from services.provider_recovery_service import (
    provider_recovery_snapshot,
    request_provider_recovery,
)
from services.owner_command_center_service import owner_command_center_snapshot
from services.owner_model_audit_service import owner_model_audit_snapshot
from services.owner_action_service import (
    set_alert_acknowledgement,
    set_prop_quarantine,
)
from services.readiness_service import production_readiness
from services.acceptance_service import production_acceptance_snapshot
from services.launch_control_service import launch_control_snapshot
from services.billing_certification_service import billing_release_certification
from services.grading_review_service import grading_review_queue
from services.prop_learning_service import (
    grade_learning_results,
    learning_performance_summary,
    snapshot_all_props_for_learning,
)
from services.user_feedback_service import list_feedback, submit_feedback
from services.member_signup_service import record_member_join
from services.strikeout_quality_service import (
    get_strikeout_release_controls,
    update_strikeout_release_controls,
)

router = APIRouter(prefix="/api/operations", tags=["operations"])


class StrikeoutControlPatch(BaseModel):
    controls: dict[str, object]


class ProviderRecoveryRequest(BaseModel):
    targetSport: str = "ALL"


class OwnerPropControlRequest(BaseModel):
    targetKey: str
    quarantined: bool
    reason: str
    snapshot: dict[str, object]


class OwnerAlertAcknowledgementRequest(BaseModel):
    alertKey: str
    count: int = 0
    acknowledged: bool
    reason: str


class UserFeedbackRequest(BaseModel):
    category: str = "suggestion"
    message: str
    page: str = ""
    metadata: dict[str, object] | None = None


class MemberJoinedRequest(BaseModel):
    email: str = ""
    source: str = "app"


@router.get("/readiness", dependencies=[Depends(require_owner)])
def readiness() -> dict[str, object]:
    return production_readiness()


@router.get("/acceptance", dependencies=[Depends(require_owner)])
def acceptance() -> dict[str, object]:
    return production_acceptance_snapshot()


@router.get("/release-gate")
def release_gate() -> dict[str, object]:
    """Expose only non-sensitive release pass/fail state for deployment automation."""
    acceptance_snapshot = production_acceptance_snapshot()
    billing = billing_release_certification()
    critical = acceptance_snapshot.get("status") == "critical"
    billing_ready = billing.get("releaseReady") is True
    return {
        "releaseReady": not critical and billing_ready,
        "acceptanceStatus": acceptance_snapshot.get("status", "unknown"),
        "billingReady": billing_ready,
        "criticalIssueCount": sum(
            1 for issue in acceptance_snapshot.get("issues", [])
            if isinstance(issue, dict) and issue.get("severity") == "critical"
        ),
    }


@router.get("/pipelines", dependencies=[Depends(require_owner)])
def pipelines(limit: int = 25) -> dict[str, object]:
    bounded_limit = max(1, min(limit, 100))
    runs = recent_pipeline_runs(bounded_limit)
    return {"runs": runs, **summarize_pipeline_health(runs)}


@router.get("/provider-availability", dependencies=[Depends(require_owner)])
def provider_availability() -> dict[str, object]:
    return provider_availability_snapshot()


@router.get("/provider-recovery", dependencies=[Depends(require_owner)])
def provider_recovery() -> dict[str, object]:
    return provider_recovery_snapshot()


@router.post("/provider-recovery", dependencies=[Depends(require_owner)])
def start_provider_recovery(payload: ProviderRecoveryRequest) -> dict[str, object]:
    try:
        return request_provider_recovery(payload.targetSport)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get("/command-center", dependencies=[Depends(require_owner)])
def command_center(
    window: str = "today",
    start: str | None = None,
    end: str | None = None,
) -> dict[str, object]:
    try:
        return owner_command_center_snapshot(window, start=start, end=end)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

@router.post("/command-center/prop-control")
def command_center_prop_control(
    payload: OwnerPropControlRequest,
    owner_id: str = Depends(require_owner),
) -> dict[str, object]:
    try:
        return set_prop_quarantine(
            target_key=payload.targetKey, quarantined=payload.quarantined,
            reason=payload.reason, actor_user_id=owner_id,
            snapshot=payload.snapshot,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@router.post("/command-center/alert-acknowledgement")
def command_center_alert_acknowledgement(
    payload: OwnerAlertAcknowledgementRequest,
    owner_id: str = Depends(require_owner),
) -> dict[str, object]:
    try:
        return set_alert_acknowledgement(
            alert_key=payload.alertKey, count=payload.count,
            acknowledged=payload.acknowledged, reason=payload.reason,
            actor_user_id=owner_id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@router.get("/model-audit", dependencies=[Depends(require_owner)])
def model_audit(
    window: str = "30d",
    start: str | None = None,
    end: str | None = None,
    limit: int = 500,
) -> dict[str, object]:
    try:
        return owner_model_audit_snapshot(
            window, start=start, end=end, limit=limit,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

@router.get("/control-panel", dependencies=[Depends(require_owner)])
def control_panel() -> dict[str, object]:
    return launch_control_snapshot()


@router.get("/billing-certification", dependencies=[Depends(require_owner)])
def billing_certification() -> dict[str, object]:
    """Return the billing release gate without building the full owner report."""
    return billing_release_certification()


@router.get("/control-panel/detail/{metric}", dependencies=[Depends(require_owner)])
def control_panel_detail(metric: str, limit: int = 50) -> dict[str, object]:
    """The rows behind one control-panel tile."""
    return operations_detail(metric, limit=limit)


@router.get("/grading-review", dependencies=[Depends(require_owner)])
def grading_review() -> dict[str, object]:
    return grading_review_queue()


@router.post("/prop-learning/snapshot", dependencies=[Depends(require_owner)])
def run_prop_learning_snapshot() -> dict[str, object]:
    return snapshot_all_props_for_learning()


@router.post("/prop-learning/grade", dependencies=[Depends(require_owner)])
def run_prop_learning_grade() -> dict[str, object]:
    return grade_learning_results()


@router.get("/prop-learning/performance", dependencies=[Depends(require_owner)])
def get_prop_learning_performance(days: int = 30) -> dict[str, object]:
    bounded_days = max(1, min(int(days), 365))
    return learning_performance_summary(bounded_days)


@router.get("/strikeout-controls", dependencies=[Depends(require_owner)])
def strikeout_controls() -> dict[str, object]:
    return get_strikeout_release_controls()


@router.post("/strikeout-controls", dependencies=[Depends(require_owner)])
def update_strikeout_controls(payload: StrikeoutControlPatch) -> dict[str, object]:
    return update_strikeout_release_controls(payload.controls)


@router.post("/feedback")
def submit_user_feedback(
    payload: UserFeedbackRequest,
    user_id: str = Depends(require_user_id),
) -> dict[str, object]:
    return submit_feedback(
        user_id,
        category=payload.category,
        message=payload.message,
        page=payload.page,
        metadata=payload.metadata,
    )


@router.get("/feedback", dependencies=[Depends(require_owner)])
def owner_feedback(limit: int = 50, status: str = "") -> dict[str, object]:
    return list_feedback(limit=limit, status=status)


@router.post("/member-joined")
def member_joined(
    payload: MemberJoinedRequest,
    user_id: str = Depends(require_user_id),
) -> dict[str, object]:
    return record_member_join(
        user_id,
        email=payload.email,
        source=payload.source,
    )
