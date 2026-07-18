from services.vector_similarity_service import stretch_embedding


def test_stretch_embedding_is_fixed_and_shape_sensitive() -> None:
    rising = stretch_embedding([10, 12, 14, 16, 18])
    falling = stretch_embedding([18, 16, 14, 12, 10])
    assert len(rising) == 16
    assert len(falling) == 16
    assert rising != falling
    assert rising == stretch_embedding([10, 12, 14, 16, 18])


def test_constant_stretch_embedding_is_finite() -> None:
    result = stretch_embedding([20, 20, 20, 20, 20])
    assert len(result) == 16
    assert all(abs(value) < 100 for value in result)
