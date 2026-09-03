-- The original table constraint capped every chat message at 500 characters
-- before the owner-aware trigger could apply its exception. Keep non-empty
-- validation here; the trigger securely retains the 500-character member cap.

begin;

alter table public.prop_chat_messages
  drop constraint if exists prop_chat_messages_body_check;

alter table public.prop_chat_messages
  add constraint prop_chat_messages_body_check
  check (char_length(trim(body)) > 0);

commit;
