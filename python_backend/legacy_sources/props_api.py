from typing import Any

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(
    title="PROP INTELLIGENCE API",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/props")
def get_props() -> dict[str, list[dict[str, Any]]]:
    return {
        "props": [
            {
                "id": "shohei-ohtani-total-bases",
                "player": "Shohei Ohtani",
                "sport": "MLB",
                "matchup": "Dodgers @ Giants",
                "sportsbook": "PrizePicks",
                "market": "Total Bases",
                "line": 1.5,
                "pick": "OVER",
                "edge": 58,
                "imagePath": "assets/players/shohei_ohtani.png",
            },
            {
                "id": "chelsea-gray-assists",
                "player": "Chelsea Gray",
                "sport": "WNBA",
                "matchup": "Fever @ Aces",
                "sportsbook": "DraftKings",
                "market": "Assists",
                "line": 6.5,
                "pick": "OVER",
                "edge": 60,
                "imagePath": "assets/players/chelsea_gray.png",
            },
        ]
    }
