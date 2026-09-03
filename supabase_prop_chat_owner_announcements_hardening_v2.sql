-- Supabase may retain explicit API-role grants in addition to PostgreSQL's
-- default PUBLIC function grant. This trigger function is never called by a
-- client, so remove every direct PostgREST execution path.

begin;

revoke all on function public.enforce_prop_chat_message_length_and_announcement()
from public, anon, authenticated;

commit;
