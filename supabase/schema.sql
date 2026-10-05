-- Vinyl Player: accounts, friends and shared records.
-- Run this once in your Supabase project: SQL Editor → New query → paste → Run.
-- Also turn on Authentication → Sign In / Providers → "Allow anonymous sign-ins".

-- Profiles: one per account, found by username.
create table if not exists public.profiles (
  id uuid primary key references auth.users on delete cascade,
  username text not null unique check (username ~ '^[a-z0-9_]{3,20}$'),
  display_name text check (char_length(display_name) <= 40),
  pet text check (char_length(pet) <= 20),
  created_at timestamptz not null default now()
);

-- Friends: "user_id added friend_id". Either direction counts as friends in the app.
create table if not exists public.friendships (
  user_id uuid not null references public.profiles on delete cascade,
  friend_id uuid not null references public.profiles on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);

-- Shared records.
create table if not exists public.shares (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null default auth.uid() references public.profiles on delete cascade,
  recipient_id uuid not null references public.profiles on delete cascade,
  title text not null check (char_length(title) <= 200),
  artist text not null check (char_length(artist) <= 200),
  spotify_id text check (spotify_id ~ '^[A-Za-z0-9]{22}$'),
  artwork_url text check (artwork_url ~ '^https://'),
  message text check (char_length(message) <= 140),
  pet text check (char_length(pet) <= 20),
  created_at timestamptz not null default now(),
  opened_at timestamptz,
  check (sender_id <> recipient_id)
);
create index if not exists shares_recipient_idx on public.shares (recipient_id, created_at desc);
create index if not exists shares_sender_idx on public.shares (sender_id, created_at desc);

alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.shares enable row level security;

-- Nobody signed out can read anything.
revoke all on public.profiles, public.friendships, public.shares from anon;

-- Profiles: any signed-in user can look people up; you can only create and edit your own.
drop policy if exists "profiles readable" on public.profiles;
create policy "profiles readable" on public.profiles for select to authenticated using (true);
drop policy if exists "own profile insert" on public.profiles;
create policy "own profile insert" on public.profiles for insert to authenticated with check (id = auth.uid());
drop policy if exists "own profile update" on public.profiles;
create policy "own profile update" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- Friendships: you see the ones you're part of; you can add and remove your own.
drop policy if exists "friendships visible" on public.friendships;
create policy "friendships visible" on public.friendships for select to authenticated
  using (user_id = auth.uid() or friend_id = auth.uid());
drop policy if exists "add friend" on public.friendships;
create policy "add friend" on public.friendships for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "remove friend" on public.friendships;
create policy "remove friend" on public.friendships for delete to authenticated using (user_id = auth.uid());

-- Shares: senders and recipients see them; you can only send as yourself;
-- recipients can only mark a record as opened.
drop policy if exists "shares visible" on public.shares;
create policy "shares visible" on public.shares for select to authenticated
  using (sender_id = auth.uid() or recipient_id = auth.uid());
drop policy if exists "send share" on public.shares;
create policy "send share" on public.shares for insert to authenticated with check (sender_id = auth.uid());
drop policy if exists "open share" on public.shares;
create policy "open share" on public.shares for update to authenticated
  using (recipient_id = auth.uid()) with check (recipient_id = auth.uid());
drop policy if exists "delete share" on public.shares;
create policy "delete share" on public.shares for delete to authenticated
  using (recipient_id = auth.uid() or sender_id = auth.uid());

revoke update on public.shares from authenticated;
grant update (opened_at) on public.shares to authenticated;

-- Limit sending to 60 records an hour per person.
create or replace function public.limit_shares() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.shares where sender_id = new.sender_id and created_at > now() - interval '1 hour') >= 60 then
    raise exception 'Too many records sent in the last hour';
  end if;
  return new;
end $$;
drop trigger if exists shares_rate_limit on public.shares;
create trigger shares_rate_limit before insert on public.shares for each row execute function public.limit_shares();

-- Listening together: what each person is spinning right now (shown to friends in the app).
-- Safe to run again on an existing project.
alter table public.profiles add column if not exists now_title text check (char_length(now_title) <= 200);
alter table public.profiles add column if not exists now_artist text check (char_length(now_artist) <= 200);
alter table public.profiles add column if not exists now_spotify_id text check (now_spotify_id ~ '^[A-Za-z0-9]{22}$');
alter table public.profiles add column if not exists now_artwork_url text check (now_artwork_url ~ '^https://');
alter table public.profiles add column if not exists now_playing boolean not null default false;
alter table public.profiles add column if not exists now_updated_at timestamptz;
