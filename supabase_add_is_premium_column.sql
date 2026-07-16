-- Adds admin/premium role flag to user_profiles.
-- Run in Supabase SQL Editor.

alter table public.user_profiles
add column if not exists is_premium boolean not null default false;

-- Optional helper: promote your account immediately by email.
-- update public.user_profiles
-- set is_premium = true
-- where email = 'admin@example.com';
