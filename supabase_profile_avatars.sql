-- Secure per-member profile photos used by every responsive PI layout.
begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'profile-avatars',
  'profile-avatars',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "members upload their profile avatar" on storage.objects;
create policy "members upload their profile avatar"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'profile-avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "members update their profile avatar" on storage.objects;
create policy "members update their profile avatar"
on storage.objects for update to authenticated
using (
  bucket_id = 'profile-avatars'
  and owner_id = auth.uid()::text
)
with check (
  bucket_id = 'profile-avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "members remove their profile avatar" on storage.objects;
create policy "members remove their profile avatar"
on storage.objects for delete to authenticated
using (
  bucket_id = 'profile-avatars'
  and owner_id = auth.uid()::text
);

commit;
