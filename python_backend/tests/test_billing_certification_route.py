from routers import operations


def test_billing_certification_uses_lightweight_release_gate(monkeypatch) -> None:
    expected = {"status": "PASS", "releaseReady": True, "checks": []}
    monkeypatch.setattr(
        operations,
        "billing_release_certification",
        lambda: expected,
    )

    assert operations.billing_certification() == expected
