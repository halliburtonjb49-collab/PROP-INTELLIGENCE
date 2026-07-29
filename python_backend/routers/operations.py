"""Protected production-readiness and pipeline monitoring endpoints."""

from fastapi import APIRouter, Depends

from services.api_auth_service import require_admin, require_owner
from services.pipeline_run_service import recent_pipeline_runs, summarize_pipeline_health
from services.readiness_service import production_readiness
from services.acceptance_service import production_acceptance_snapshot
from services.launch_control_service import launch_control_snapshot
from services.grading_review_service import grading_review_queue

router = APIRouter(prefix="/api/operations", tags=["operations"])


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
