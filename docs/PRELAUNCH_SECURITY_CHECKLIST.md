# PROP INTELLIGENCE pre-launch security checklist

## Enforced in the repository

- PostgreSQL clients require TLS with `DATABASE_SSLMODE=require`.
- Every table in the exposed `public` schema has RLS enabled by
  `supabase_security_hardening.sql`.
- Proprietary model, prediction, market-intelligence, and billing tables are
  revoked from browser roles and available only through the authenticated API.
- Free/Core/Pro/Admin/Owner authorization is resolved by the server.
- Player search, prop feeds, realtime chat, ticket creation, scoreboards, and
  Pro calculations have independent Redis-backed limits.
- Access denials, rate-limit blocks, ticket creation, and Pro calculation
  access are written to `security_events` using a one-way actor hash. Tokens
  and email addresses are never stored.
- `tools/verify_postgres_backup_restore.py` refuses to restore over production
  and requires an explicit disposable restore database.

## Live provider controls that require the owner account

Complete and record the date and evidence for each item:

- Supabase Security Advisor has no unresolved errors.
- Supabase Auth CAPTCHA is enabled for signup, password sign-in, and recovery.
  Do not enable enforcement until the matching client CAPTCHA widget and site
  key are deployed.
- Supabase database network restrictions allow only approved service egress
  addresses where the selected plan supports them.
- Supabase managed daily backups or PITR are enabled.
- GitHub owner account has MFA and recovery codes stored offline.
- Render owner account has MFA and recovery codes stored offline.
- Supabase owner account has MFA and recovery codes stored offline.
- A disposable restore project/database has passed
  `verify_postgres_backup_restore.py`; record the backup timestamp, restore
  target, duration, row/table validation, and deletion time.

Never place MFA recovery codes, CAPTCHA secrets, database passwords, API keys,
or screenshots containing secrets in this repository.
