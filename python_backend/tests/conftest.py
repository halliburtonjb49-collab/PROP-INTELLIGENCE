import pytest

import main
from services.api_auth_service import AccessLevel, Membership, require_core, require_pro
from services import rate_limit_service


@pytest.fixture(autouse=True)
def authenticated_pro_dependencies():
    """Keep existing API tests authenticated while each security test can override."""
    membership = Membership("test-pro-user", AccessLevel.PRO, "pro", "user")
    previous_core = main.app.dependency_overrides.get(require_core)
    previous_pro = main.app.dependency_overrides.get(require_pro)
    main.app.dependency_overrides[require_core] = lambda: membership
    main.app.dependency_overrides[require_pro] = lambda: membership
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
