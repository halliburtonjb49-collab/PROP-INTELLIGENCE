from datetime import datetime, timedelta, timezone

import pytest

import main
from services import api_auth_service, rate_limit_service
from services.api_auth_service import AccessLevel, Membership, require_core, require_pro


@pytest.fixture(autouse=True)
def authenticated_pro_dependencies():
    """Keep existing API tests authenticated while each security test can override."""
    membership = Membership("test-pro-user", AccessLevel.PRO, "pro", "user")
    previous_core = main.app.dependency_overrides.get(require_core)
    previous_pro = main.app.dependency_overrides.get(require_pro)
    main.app.dependency_overrides[require_core] = lambda: membership
    main.app.dependency_overrides[require_pro] = lambda: membership
    api_auth_service.clear_membership_cache()
    rate_limit_service._memory_buckets.clear()
    yield
    if previous_core is None:
        main.app.dependency_overrides.pop(require_core, None)
    else:
        main.app.dependency_overrides[require_core] = previous_core
    if previous_pro is None:
        main.app.dependency_overrides.pop(require_pro, None)
    else:
        main.app.dependency_overrides[require_pro] = previous_pro
    api_auth_service.clear_membership_cache()


@pytest.fixture
def recently_observed():
    """Build a lineup timestamp the staleness gate accepts, on any date.

    Hardcoding an observation time makes a test pass only on the day it was
    written; afterwards the staleness gate fires first and hides the gate the
    test is actually about.
    """

    def _timestamp(minutes_ago: int = 5) -> str:
        observed = datetime.now(timezone.utc) - timedelta(minutes=minutes_ago)
        return observed.strftime("%Y-%m-%dT%H:%M:%SZ")

    return _timestamp
