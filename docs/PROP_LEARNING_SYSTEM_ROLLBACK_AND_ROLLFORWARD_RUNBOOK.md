# PROP Learning System Runbook

## Scope

This runbook covers migration + API rollout for the closed-loop prop learning system:

- `supabase_prop_learning_system.sql`
- Endpoints:
  - `POST /api/operations/prop-learning/snapshot`
  - `POST /api/operations/prop-learning/grade`
  - `GET /api/operations/prop-learning/performance`

## Prerequisites

- DATABASE_URL set in shell/environment for migrations.
- Owner authentication available for ops endpoints (owner token/session).
- Service can connect to Supabase Postgres and API successfully.
- No active DB schema migration currently running.

## Step 1 — Apply migration

From repo root:

```powershell
$env:DATABASE_URL='postgresql://...'
.\.venv\Scripts\python.exe python_backend\scripts\apply_supabase_migrations.py
```

Expected:
- No migration checksum errors.
- Runner prints `Supabase migrations are current.` at the end.

If failed, capture the exact Python exception and resolve before continuing.

## Step 2 — Verify new tables exist in SQL editor (optional but recommended)

Run a quick verification query in Supabase SQL:

```sql
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in (
    'prop_prediction_snapshots',
    'prop_results',
    'model_performance_metrics'
  );
```

Expected: all 3 rows returned.

## Step 3 — Seed snapshots

Call:

```bash
POST https://api.propsintell.com/api/operations/prop-learning/snapshot
```

Expected response:
- `created` integer
- `snapshotDate` current UTC date
- `skipped` object with `stale`/`invalid`

Interpretation:
- Non-zero `created` means new live-board props were snapshot for grading.
- Zero is acceptable during off-slates.

## Step 4 — Grade snapshot outcomes

Call:

```bash
POST https://api.propsintell.com/api/operations/prop-learning/grade
```

Expected response fields:
- `graded`
- `pendingChecked`
- `unsupported`
- `errors`
- `stateCounts` (WIN/LOSS/PUSH/PENDING/ERROR)
- `pendingReasons`
- `backlogTotal`
- `backlogOldestEventTime`
- `gradedAt`

| Endpoint | Expected minimum fields |
|---|---|
| `POST /api/operations/prop-learning/snapshot` | `created`, `snapshotDate`, `skipped` |
| `POST /api/operations/prop-learning/grade` | `graded`, `pendingChecked`, `stateCounts`, `gradedAt` |
| `GET /api/operations/prop-learning/performance` | `available`, `windowDays`, `totals`, `metrics` |

Interpretation:
- `stateCounts` should move non-zero over repeated runs.
- `pending` may include unresolved matches; this is expected on early checks.
- `errors` should stay low; investigate sudden spikes.

## Step 5 — Read performance summary

Call:

```bash
GET https://api.propsintell.com/api/operations/prop-learning/performance?days=30
```

Expected response fields:
- `windowDays`
- `available: true`
- `totals.pending`
- `metrics` array with metric rows

Interpretation:
- Confirm rows are generated for recent metric dates.
- Ensure pending count trends toward zero as events resolve.

## Pipeline status check during normal sync

The global sync pipeline now includes:

- `prop_learning_snapshot` post-processing step after alerts.
- `prop_learning_grade` during grading cooldown block.

In sync logs/results, confirm both step labels appear.

## Troubleshooting

- Empty metrics with non-empty tables:
  - Confirm grade endpoint has been allowed to run during cooldown windows.
  - Confirm `model_performance_metrics` table contains recent rows.
- Many `unsupported` outcomes:
  - Check source APIs and market mapping (`sport`, `market`, and `event_time`).
  - Verify official MLB / historical logs contain matching names and start times.
- Many `pending` with old events:
  - Confirm source services are healthy.
  - Backfill / replay grading cycle after source recovery.

## Rollback plan

- **Code rollback:** revert this repository commit and redeploy backend.
- **Schema rollback:** do not drop tables in-place without a migration decision and data retention review.
- **Operational rollback:** stop calling the two new ops endpoints and skip the new sync post-processing steps if grading introduces unacceptable production risk.

## Compliance note

The migration enforces:
- forced RLS on learning tables
- revoked direct access for `anon` and `authenticated`
- owner-only policies using `public.is_app_owner(auth.uid())`

These constraints are required for production hardening and are validated by migration checks.
