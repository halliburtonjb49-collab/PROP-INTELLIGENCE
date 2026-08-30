"""Scheduled identity/media catalog reconciliation."""
import json
from services.identity_media_registry_service import reconcile_catalog
from services.prop_catalog_snapshot_service import load_catalog_snapshot
def main() -> int:
    result = reconcile_catalog(load_catalog_snapshot()); print(json.dumps(result, default=str)); return 0
if __name__ == "__main__": raise SystemExit(main())

