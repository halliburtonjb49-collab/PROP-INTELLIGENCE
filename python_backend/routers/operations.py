"""Protected production-readiness and pipeline monitoring endpoints."""

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from services.api_auth_service import require_admin, require_owner, require_user_id
from services.pipeline_run_service import recent_pipeline_runs, summarize_pipeline_health
from services.readiness_service import production_readiness
from services.acceptance_service import production_acceptance_snapshot
from services.launch_control_service import launch_control_snapshot
from services.grading_review_service import grading_review_queue
from services.user_feedback_service import list_feedback, submit_feedback
from services.member_signup_service import record_member_join
from services.strikeout_quality_service import (
    get_strikeout_release_controls,
    update_strikeout_release_controls,
)

router = APIRouter(prefix="/api/operations", tags=["operations"])


class StrikeoutControlPatch(BaseModel):
    controls: dict[str, object]


class UserFeedbackRequest(BaseModel):
    category: str = "suggestion"
    message: str
    page: str = ""
    metadata: dict[str, object] | None = None


class MemberJoinedRequest(BaseModel):
    email: str = ""
    source: str = "app"


@router.get("/readiness", dependencies=[Depends(require_admin)])
def readiness() -> dict[str, object]:
    return production_readiness()


@router.get("/acceptance", dependencies=[Depends(require_owner)])
def acceptance() -> dict[str, object]:
    return production_acceptance_snapshot()


@router.get("/pipelines", dependencies=[Depends(require_admin)])
def pipelines(limit: int = 25) -> dict[str, object]:
    bounded_limit = max(1, min(limit, 100))
    runs = recent_pipeline_runs(bounded_limit)
    return {"runs": runs, **summarize_pipeline_health(runs)}


@router.get("/control-panel", dependencies=[Depends(require_owner)])
def control_panel() -> dict[str, object]:
    return launch_control_snapshot()


@router.get("/grading-review", dependencies=[Depends(require_owner)])
def grading_review() -> dict[str, object]:
    return grading_review_queue()


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
