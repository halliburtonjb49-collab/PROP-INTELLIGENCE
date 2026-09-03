-- Trigger functions execute through their trigger and must not be callable
-- directly through PostgREST by anonymous or authenticated clients.

begin;

revoke all on function public.enforce_prop_chat_message_length_and_announcement()
from public;

commit;
