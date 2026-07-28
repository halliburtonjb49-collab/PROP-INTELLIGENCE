"""Entrypoints executed by the durable RQ worker."""


def run_prop_sync() -> None:
    import main

    main.run_queued_prop_sync()
    # Publish the worker's refreshed catalog to Redis so the web service can
    # consume it even though Render service disks are intentionally isolated.
    main._cached_prop_catalog()
