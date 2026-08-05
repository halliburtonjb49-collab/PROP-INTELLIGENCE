# Strikeout Ops Runbooks and SLAs

This document defines alert ownership, response SLAs, and postmortem requirements for MLB strikeout operations.

## Alert Tiers and Ownership

- warning: owner responds during business-hours triage and tracks trend.
- critical: on-call owner acknowledges and mitigates under critical SLA.

Default owners by failure mode:

- stale_data: data-platform
- calibration_drift: model-ops
- ingest_failure: data-platform
- deploy_failure: release-engineering
- grading_mismatch: grading-ops

## Response SLAs

- acknowledge: 10 minutes for critical alerts
- mitigate: 60 minutes for critical alerts
- update cadence: every 30 minutes until mitigated

## Auto Incident Policy

- Any critical alert from strikeout quality monitoring auto-opens an incident record.
- Incident records include SLA metadata and postmortem due time.

## Runbooks

### 1) stale_data

Signals:

- no fresh strikeout predictions within expected cadence
- old lineup snapshots or aging feed timestamps

Immediate actions:

- validate source API health and credential status
- run sync job manually
- verify new snapshots are written to prediction_snapshots

Mitigation:

- switch to safe mode inputs if source is degraded
- update owner dashboard with expected recovery time

### 2) calibration_drift

Signals:

- calibration gap guardrail warning or critical breach
- sustained hit-rate delta vs predicted in fixed windows

Immediate actions:

- identify affected slices (book, line band, handedness, side)
- disable risky slice publishing if hard breach persists

Mitigation:

- apply conservative calibration adjustment only
- verify next cycle reports return within guardrails

### 3) ingest_failure

Signals:

- abrupt drop in snapshot volume
- repeated pipeline ingestion errors

Immediate actions:

- inspect ingestion logs and provider status
- rerun failed ingestion tasks

Mitigation:

- backfill missing interval
- confirm end-to-end write path is healthy

### 4) deploy_failure

Signals:

- workflow/deploy job failed
- release artifact not promoted

Immediate actions:

- identify failed step from CI logs
- execute rollback to last known good commit if user impact exists

Mitigation:

- restore stable build and rerun deployment checks
- document failure signature for future prevention

### 5) grading_mismatch

Signals:

- graded outcomes mismatch with official stat source
- unusual spike in unresolved/unsupported grading reasons

Immediate actions:

- verify player identity and market mapping
- replay grading for impacted snapshots only

Mitigation:

- patch mapping logic and add regression test coverage
- run targeted backfill for impacted dates

## Postmortem Template (required within 24h)

- trigger:
- blast radius:
- root cause:
- permanent fix:
- follow-up owner/date:
