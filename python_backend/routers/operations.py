"""Protected production-readiness and pipeline monitoring endpoints."""

from fastapi import APIRouter, Depends

from services.api_auth_service import require_admin, require_owner
from services.pipeline_run_service import recent_pipeline_runs
from services.readiness_service import production_readiness
from services.acceptance_service import production_acceptance_snapshot

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
    failures = [run for run in runs if run["status"] not in {"SUCCEEDED"}]
    return {"runs": runs, "failures": failures, "healthy": not failures}
