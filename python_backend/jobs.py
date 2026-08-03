"""Entrypoints executed by the durable RQ worker."""


def run_prop_sync() -> None:
    """Run and publish recovery entirely on the dedicated RQ worker."""
    import main

    main.run_queued_prop_sync()
    # The worker and API have separate ephemeral disks. Publish the worker's
    # completed local catalog to Redis so API instances and devices can read it.
    props = main._cached_prop_catalog()
    main.save_catalog_snapshot(
        [prop.model_dump(mode="json") for prop in props]
    )


def fetch_sport_raw(sport: str) -> dict[str, object]:
    from services.raw_ingestion_service import fetch_sport_to_stream

    return fetch_sport_to_stream(sport)


def fetch_sportsgameodds_raw() -> dict[str, object]:
    from services.raw_ingestion_service import fetch_sportsgameodds_to_stream

    return fetch_sportsgameodds_to_stream()


def normalize_raw_feed(message_id: str) -> dict[str, object]:
    import main
    from providers.sportsgameodds import normalize_event
    from services import raw_ingestion_service

    # SportsGameOdds streams untouched provider events, so transformation
    # happens here—not in the fetch job.
    client = raw_ingestion_service._redis()
    if client is None:
        raise RuntimeError("Redis unavailable")
    messages = client.xrange(
        raw_ingestion_service.STREAM_NAME,
        min=message_id,
        max=message_id,
        count=1,
    )
    if messages:
        _, fields = messages[0]
        encoded = fields.get(b"payload") or fields.get("payload")
        envelope = raw_ingestion_service._decoder.decode(encoded)
        if envelope.provider == "sportsgameodds":
            event, payload = normalize_event(envelope.event, sport_key=envelope.sport)
            updated = raw_ingestion_service.RawFeedEnvelope(
                provider=envelope.provider,
                sport=envelope.sport,
                event=event,
                payload=payload,
                fetched_at=envelope.fetched_at,
            )
            normalized_id = client.xadd(
                raw_ingestion_service.STREAM_NAME,
                {"payload": raw_ingestion_service._encoder.encode(updated)},
                maxlen=raw_ingestion_service.STREAM_MAXLEN,
                approximate=True,
            )
            message_id = (
                normalized_id.decode()
                if isinstance(normalized_id, bytes)
                else str(normalized_id)
            )
    result = raw_ingestion_service.normalize_stream_message(message_id)
    main._invalidate_prop_catalog()
    main._cached_prop_catalog()
    return result
