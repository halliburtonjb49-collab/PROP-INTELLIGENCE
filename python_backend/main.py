from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from app.routes.scoreboard import router as scoreboard_router

app = FastAPI(
    title="The Daily Spin API",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(scoreboard_router, prefix="/api")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/props")
def get_props() -> dict[str, list[dict[str, Any]]]:
    raise HTTPException(
        status_code=503,
        detail=(
            "Workspace stub backend does not serve live props. "
            "Run the real backend from ../python_backend instead."
        ),
    )
