from services import prediction_automation_service as automation


class _Cursor:
    def __init__(self, rows, recorder):
        self.rows = rows
        self.recorder = recorder

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def execute(self, query, params=None):
        self.recorder.append((" ".join(str(query).split()), params))

    def fetchall(self):
        return self.rows


class _Connection:
    def __init__(self, rows, recorder):
        self.rows = rows
        self.recorder = recorder

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def cursor(self):
        return _Cursor(self.rows, self.recorder)


def _run(monkeypatch, rows):
    recorder: list = []
    monkeypatch.setattr(automation, "database_is_configured", lambda: True)
    monkeypatch.setattr(
        automation,
        "get_database_pool",
        lambda: type(
            "Pool", (), {"connection": lambda _self: _Connection(rows, recorder)}
        )(),
    )
    return automation.model_probability_reliability(minimum_bucket=10), recorder


def test_the_overstating_tail_is_reported_as_overstatement(monkeypatch):
    """Props the model calls 96% land nearer two thirds.

    They stay profitable because the ordering is sound and the prices are
    good, so this is a defect in what the number claims rather than in which
    props it picks. It has to be visible as exactly that.
    """

    report, _ = _run(monkeypatch, [(7, 1162, 0.9632, 0.6411)])

    assert report[0]["overstatement"] > 0.3
    assert report[0]["predictedProbability"] == 0.9632
    assert report[0]["observedHitRate"] == 0.6411


def test_a_well_calibrated_band_shows_no_overstatement(monkeypatch):
    report, _ = _run(monkeypatch, [(1, 4363, 0.4666, 0.4722)])

    assert abs(float(report[0]["overstatement"])) < 0.01


def test_reliability_reads_the_estimate_not_the_conservative_floor(monkeypatch):
    """hit_probability is the calibrated probability minus a safety margin.

    Measuring a floor against outcomes describes the margin working as
    designed, not a defect, and reading it as one already cost an afternoon.
    """

    _report, recorder = _run(monkeypatch, [])
    query = recorder[0][0]

    assert "inputs->>'modelProbability'" in query
    assert "hit_probability" not in query


def test_thin_buckets_are_withheld(monkeypatch):
    report, _ = _run(monkeypatch, [])

    assert report == []
