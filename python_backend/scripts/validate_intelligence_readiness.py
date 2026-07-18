import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from services.readiness_service import production_readiness


if __name__ == "__main__":
    result = production_readiness()
    print(json.dumps(result, indent=2, default=str))
    raise SystemExit(0 if result["status"] == "ready" else 1)
