begin;

alter table public.user_profiles
  add column if not exists subscription_tier text not null default 'free'
  check (subscription_tier in ('free', 'core', 'edge'));

-- Preserve existing customers as full Edge members during the migration.
update public.user_profiles set subscription_tier = 'edge'
where is_premium = true and subscription_tier = 'free';

-- Subscription state must only be changed by the trusted backend/webhook role.
revoke update (subscription_tier, is_premium) on public.user_profiles from authenticated;

create index if not exists user_profiles_subscription_tier_idx
  on public.user_profiles(subscription_tier);

commit;
