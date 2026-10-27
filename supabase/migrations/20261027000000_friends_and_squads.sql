-- Friends, squads and accountability.
--
-- People add each other with a six-character invite code. Each person shares one small daily
-- summary (movement goal, steps, minutes earned, streak); never which apps they protect or how
-- they spent their minutes. When a finished day falls short of its goal, friends get one
-- "missed their goal" event (and a push, when APNs is configured). Squads of up to ten compare
-- days on goal and minutes earned in a Monday-to-Sunday league.
--
-- Everything goes through the `social` Edge Function with the service role, like the exercise
-- backend: no table is readable by `anon` or `authenticated`.

create table public.social_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(btrim(display_name)) between 1 and 24),
  invite_code text not null unique check (invite_code ~ '^[A-HJ-NP-Z2-9]{6}$'),
  share_misses boolean not null default true,
  apns_token text check (apns_token is null or apns_token ~ '^[0-9a-f]{64,200}$'),
  apns_environment text check (apns_environment is null or apns_environment in ('sandbox', 'production')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.friendships (
  user_low uuid not null references public.social_profiles(user_id) on delete cascade,
  user_high uuid not null references public.social_profiles(user_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_low, user_high),
  check (user_low < user_high)
);

create index friendships_user_high_idx on public.friendships (user_high);

create table public.squads (
  id uuid primary key default extensions.gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 32),
  invite_code text not null unique check (invite_code ~ '^[A-HJ-NP-Z2-9]{6}$'),
  created_by uuid not null references public.social_profiles(user_id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.squad_members (
  squad_id uuid not null references public.squads(id) on delete cascade,
  user_id uuid not null references public.social_profiles(user_id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (squad_id, user_id)
);

create index squad_members_user_idx on public.squad_members (user_id);

create table public.daily_progress (
  user_id uuid not null references public.social_profiles(user_id) on delete cascade,
  day date not null,
  daily_goal integer not null check (daily_goal between 0 and 200000),
  activity_amount integer not null check (activity_amount between 0 and 500000),
  earned_seconds integer not null check (earned_seconds between 0 and 86400),
  streak_days integer not null check (streak_days between 0 and 10000),
  is_final boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);

create table public.social_events (
  id uuid primary key default extensions.gen_random_uuid(),
  recipient_id uuid not null references public.social_profiles(user_id) on delete cascade,
  actor_id uuid not null references public.social_profiles(user_id) on delete cascade,
  kind text not null check (kind in ('missed_goal', 'nudge', 'cheer', 'friend_added')),
  day date not null,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  -- One of each kind per pair and day: a miss is reported once, and a friend can nudge or cheer
  -- someone once a day.
  unique (recipient_id, actor_id, kind, day)
);

create index social_events_recipient_idx on public.social_events (recipient_id, created_at desc);

alter table public.social_profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.squads enable row level security;
alter table public.squad_members enable row level security;
alter table public.daily_progress enable row level security;
alter table public.social_events enable row level security;

revoke all on table public.social_profiles from public, anon, authenticated;
revoke all on table public.friendships from public, anon, authenticated;
revoke all on table public.squads from public, anon, authenticated;
revoke all on table public.squad_members from public, anon, authenticated;
revoke all on table public.daily_progress from public, anon, authenticated;
revoke all on table public.social_events from public, anon, authenticated;

grant select, insert, update, delete on table public.social_profiles to service_role;
grant select, insert, update, delete on table public.friendships to service_role;
grant select, insert, update, delete on table public.squads to service_role;
grant select, insert, update, delete on table public.squad_members to service_role;
grant select, insert, update, delete on table public.daily_progress to service_role;
grant select, insert, update, delete on table public.social_events to service_role;

-- Codes skip 0/O and 1/I so they survive being read aloud or typed from a screenshot.
create or replace function private.random_invite_code()
returns text
language sql
volatile
set search_path = ''
as $$
  select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::integer, 1), '')
  from generate_series(1, 6);
$$;

create or replace function private.are_friends(p_a uuid, p_b uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1 from public.friendships
    where user_low = least(p_a, p_b) and user_high = greatest(p_a, p_b)
  );
$$;

create or replace function public.social_upsert_profile(
  p_user_id uuid,
  p_display_name text,
  p_share_misses boolean default null,
  p_apns_token text default null,
  p_apns_environment text default null
)
returns public.social_profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.social_profiles;
  v_code text;
begin
  select * into v_profile from public.social_profiles where user_id = p_user_id for update;
  if found then
    update public.social_profiles
    set display_name = coalesce(nullif(btrim(p_display_name), ''), display_name),
        share_misses = coalesce(p_share_misses, share_misses),
        apns_token = coalesce(p_apns_token, apns_token),
        apns_environment = coalesce(p_apns_environment, apns_environment),
        updated_at = now()
    where user_id = p_user_id
    returning * into v_profile;
    return v_profile;
  end if;

  if nullif(btrim(p_display_name), '') is null then
    raise exception 'display name is required' using errcode = '22023';
  end if;

  loop
    v_code := private.random_invite_code();
    exit when not exists (select 1 from public.social_profiles where invite_code = v_code)
      and not exists (select 1 from public.squads where invite_code = v_code);
  end loop;

  insert into public.social_profiles (user_id, display_name, invite_code, share_misses, apns_token, apns_environment)
  values (p_user_id, btrim(p_display_name), v_code, coalesce(p_share_misses, true), p_apns_token, p_apns_environment)
  returning * into v_profile;
  return v_profile;
end;
$$;

-- Returns the new friend's profile. Adding someone twice is not an error.
create or replace function public.social_add_friend(p_user_id uuid, p_invite_code text, p_today date)
returns public.social_profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_friend public.social_profiles;
begin
  if not exists (select 1 from public.social_profiles where user_id = p_user_id) then
    raise exception 'social profile required' using errcode = 'P0002';
  end if;
  select * into v_friend from public.social_profiles where invite_code = upper(btrim(p_invite_code));
  if not found then
    raise exception 'invite code not found' using errcode = 'P0002';
  end if;
  if v_friend.user_id = p_user_id then
    raise exception 'cannot add yourself' using errcode = '22023';
  end if;
  if private.are_friends(p_user_id, v_friend.user_id) then
    return v_friend;
  end if;
  if (select count(*) from public.friendships where p_user_id in (user_low, user_high)) >= 20
    or (select count(*) from public.friendships where v_friend.user_id in (user_low, user_high)) >= 20 then
    raise exception 'friend limit reached' using errcode = '23514';
  end if;

  insert into public.friendships (user_low, user_high)
  values (least(p_user_id, v_friend.user_id), greatest(p_user_id, v_friend.user_id))
  on conflict do nothing;
  insert into public.social_events (recipient_id, actor_id, kind, day)
  values (v_friend.user_id, p_user_id, 'friend_added', p_today)
  on conflict do nothing;
  return v_friend;
end;
$$;

-- Records a day and returns the friends to tell about a miss: the first time a finished day
-- arrives short of its goal, for someone who shares misses. Only the last three days are kept
-- current, so a phone with a wrong clock cannot rewrite history.
create or replace function public.social_record_progress(
  p_user_id uuid,
  p_day date,
  p_daily_goal integer,
  p_activity_amount integer,
  p_earned_seconds integer,
  p_streak_days integer,
  p_is_final boolean
)
returns setof uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.social_profiles;
begin
  select * into v_profile from public.social_profiles where user_id = p_user_id;
  if not found then
    raise exception 'social profile required' using errcode = 'P0002';
  end if;
  if p_day < (now() at time zone 'utc')::date - 3 or p_day > (now() at time zone 'utc')::date + 1 then
    raise exception 'day out of range' using errcode = '22023';
  end if;

  insert into public.daily_progress as progress (
    user_id, day, daily_goal, activity_amount, earned_seconds, streak_days, is_final, updated_at
  )
  values (
    p_user_id, p_day, p_daily_goal, p_activity_amount, p_earned_seconds, p_streak_days, p_is_final, now()
  )
  on conflict (user_id, day) do update
  set daily_goal = excluded.daily_goal,
      activity_amount = greatest(progress.activity_amount, excluded.activity_amount),
      earned_seconds = greatest(progress.earned_seconds, excluded.earned_seconds),
      streak_days = excluded.streak_days,
      is_final = progress.is_final or excluded.is_final,
      updated_at = now();

  if not p_is_final or not v_profile.share_misses or p_daily_goal <= 0 or p_activity_amount >= p_daily_goal then
    return;
  end if;

  return query
  with inserted as (
    insert into public.social_events (recipient_id, actor_id, kind, day)
    select case when f.user_low = p_user_id then f.user_high else f.user_low end, p_user_id, 'missed_goal', p_day
    from public.friendships f
    where p_user_id in (f.user_low, f.user_high)
    on conflict do nothing
    returning social_events.recipient_id
  )
  select inserted.recipient_id from inserted;
end;
$$;

-- `nudge` (you missed it, come on) or `cheer` (nice work). Returns false when already sent today.
create or replace function public.social_send(p_user_id uuid, p_friend_id uuid, p_kind text, p_today date)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inserted integer;
begin
  if p_kind not in ('nudge', 'cheer') then
    raise exception 'invalid kind' using errcode = '22023';
  end if;
  if not private.are_friends(p_user_id, p_friend_id) then
    raise exception 'not friends' using errcode = '42501';
  end if;
  insert into public.social_events (recipient_id, actor_id, kind, day)
  values (p_friend_id, p_user_id, p_kind, p_today)
  on conflict do nothing;
  get diagnostics v_inserted = row_count;
  return v_inserted > 0;
end;
$$;

create or replace function public.social_create_squad(p_user_id uuid, p_name text)
returns public.squads
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_squad public.squads;
  v_code text;
begin
  if not exists (select 1 from public.social_profiles where user_id = p_user_id) then
    raise exception 'social profile required' using errcode = 'P0002';
  end if;
  if (select count(*) from public.squad_members where user_id = p_user_id) >= 3 then
    raise exception 'squad limit reached' using errcode = '23514';
  end if;
  loop
    v_code := private.random_invite_code();
    exit when not exists (select 1 from public.squads where invite_code = v_code)
      and not exists (select 1 from public.social_profiles where invite_code = v_code);
  end loop;
  insert into public.squads (name, invite_code, created_by)
  values (btrim(p_name), v_code, p_user_id)
  returning * into v_squad;
  insert into public.squad_members (squad_id, user_id) values (v_squad.id, p_user_id);
  return v_squad;
end;
$$;

create or replace function public.social_join_squad(p_user_id uuid, p_invite_code text)
returns public.squads
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_squad public.squads;
begin
  if not exists (select 1 from public.social_profiles where user_id = p_user_id) then
    raise exception 'social profile required' using errcode = 'P0002';
  end if;
  select * into v_squad from public.squads where invite_code = upper(btrim(p_invite_code)) for update;
  if not found then
    raise exception 'invite code not found' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.squad_members where squad_id = v_squad.id and user_id = p_user_id) then
    return v_squad;
  end if;
  if (select count(*) from public.squad_members where user_id = p_user_id) >= 3 then
    raise exception 'squad limit reached' using errcode = '23514';
  end if;
  if (select count(*) from public.squad_members where squad_id = v_squad.id) >= 10 then
    raise exception 'squad is full' using errcode = '23514';
  end if;
  insert into public.squad_members (squad_id, user_id) values (v_squad.id, p_user_id);
  return v_squad;
end;
$$;

-- Leaving the last seat deletes the squad.
create or replace function public.social_leave_squad(p_user_id uuid, p_squad_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.squad_members where squad_id = p_squad_id and user_id = p_user_id;
  delete from public.squads s
  where s.id = p_squad_id and not exists (select 1 from public.squad_members m where m.squad_id = s.id);
end;
$$;

-- The week's league for one squad the caller belongs to: days on goal first, minutes earned to
-- break ties.
create or replace function public.social_squad_standings(p_user_id uuid, p_squad_id uuid, p_week_start date)
returns table (
  user_id uuid,
  display_name text,
  goal_days integer,
  earned_seconds integer,
  streak_days integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.squad_members m where m.squad_id = p_squad_id and m.user_id = p_user_id) then
    raise exception 'not a squad member' using errcode = '42501';
  end if;
  return query
  select
    p.user_id,
    p.display_name,
    coalesce(count(*) filter (where d.daily_goal > 0 and d.activity_amount >= d.daily_goal), 0)::integer,
    coalesce(sum(d.earned_seconds), 0)::integer,
    coalesce((
      select latest.streak_days from public.daily_progress latest
      where latest.user_id = p.user_id order by latest.day desc limit 1
    ), 0)
  from public.squad_members m
  join public.social_profiles p on p.user_id = m.user_id
  left join public.daily_progress d
    on d.user_id = m.user_id and d.day between p_week_start and p_week_start + 6
  where m.squad_id = p_squad_id
  group by p.user_id, p.display_name
  order by 3 desc, 4 desc, p.display_name;
end;
$$;

revoke execute on function private.random_invite_code() from public, anon, authenticated, service_role;
revoke execute on function private.are_friends(uuid, uuid) from public, anon, authenticated, service_role;

revoke all on function public.social_upsert_profile(uuid, text, boolean, text, text) from public, anon, authenticated;
revoke all on function public.social_add_friend(uuid, text, date) from public, anon, authenticated;
revoke all on function public.social_record_progress(uuid, date, integer, integer, integer, integer, boolean) from public, anon, authenticated;
revoke all on function public.social_send(uuid, uuid, text, date) from public, anon, authenticated;
revoke all on function public.social_create_squad(uuid, text) from public, anon, authenticated;
revoke all on function public.social_join_squad(uuid, text) from public, anon, authenticated;
revoke all on function public.social_leave_squad(uuid, uuid) from public, anon, authenticated;
revoke all on function public.social_squad_standings(uuid, uuid, date) from public, anon, authenticated;

grant execute on function public.social_upsert_profile(uuid, text, boolean, text, text) to service_role;
grant execute on function public.social_add_friend(uuid, text, date) to service_role;
grant execute on function public.social_record_progress(uuid, date, integer, integer, integer, integer, boolean) to service_role;
grant execute on function public.social_send(uuid, uuid, text, date) to service_role;
grant execute on function public.social_create_squad(uuid, text) to service_role;
grant execute on function public.social_join_squad(uuid, text) to service_role;
grant execute on function public.social_leave_squad(uuid, uuid) to service_role;
grant execute on function public.social_squad_standings(uuid, uuid, date) to service_role;
