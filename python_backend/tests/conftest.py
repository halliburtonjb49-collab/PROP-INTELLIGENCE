from datetime import datetime, timedelta, timezone

import pytest

import main
from services import (
    api_auth_service,
    operations_notification_service,
    rate_limit_service,
)
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
    with main._prop_response_cache_lock:
        main._prop_response_cache.clear()
    # _prop_catalog is process-global. A test that leaves it mutated makes a
    # later one either assert against another test's state or miss the
    # in-memory cache entirely and fall through to a real rebuild, which
    # reaches for live providers and hangs the suite rather than failing it.
    with main._prop_catalog_lock:
        saved_catalog = dict(main._prop_catalog)
    # The last alert delivery is remembered so an operations page can say
    # whether the channel works. Left standing between tests it makes a
    # healthy webhook read as rejected purely because an earlier test
    # rehearsed a failure.
    operations_notification_service._LAST_DELIVERY.clear()
    yield
    if previous_core is None:
        main.app.dependency_overrides.pop(require_core, None)
    else:
        main.app.dependency_overrides[require_core] = previous_core
    if previous_pro is None:
        main.app.dependency_overrides.pop(require_pro, None)
    else:
        main.app.dependency_overrides[require_pro] = previous_pro
    with main._prop_catalog_lock:
        main._prop_catalog.clear()
        main._prop_catalog.update(saved_catalog)
    api_auth_service.clear_membership_cache()
    with main._prop_response_cache_lock:
        main._prop_response_cache.clear()


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
