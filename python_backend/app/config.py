from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def _read_env_file_value(name: str) -> str:
    candidate_paths = (
        Path('.env'),
        Path('python_backend/.env'),
    )

    for path in candidate_paths:
        if not path.exists():
            continue

        for raw_line in path.read_text(encoding='utf-8').splitlines():
            line = raw_line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue

            key, value = line.split('=', 1)
            if key.strip() != name:
                continue

            return value.strip().strip("\"'")

    return ''


@dataclass(frozen=True)
class Settings:
    sportsdataio_api_key: str = ''


settings = Settings(
    sportsdataio_api_key=os.getenv('SPORTSDATAIO_API_KEY')
    or _read_env_file_value('SPORTSDATAIO_API_KEY'),
)
