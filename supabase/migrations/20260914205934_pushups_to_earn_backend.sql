create table public.exercise_configuration (
  id boolean primary key default true check (id),
  enabled boolean not null default true,
  entitlement_required boolean not null default true,
  entitlement_id text not null default 'Earn your Screen Time Pro' check (length(entitlement_id) between 1 and 255),
  daily_cap_seconds integer not null default 1800 check (daily_cap_seconds between 60 and 86400),
  session_ttl_seconds integer not null default 900 check (session_ttl_seconds between 60 and 3600),
  minimum_app_version text not null default '0.1.0' check (minimum_app_version ~ '^[0-9]{1,9}(\.[0-9]{1,9}){0,2}$'),
  detection_version text not null default '1' check (detection_version ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'),
  minimum_pose_confidence numeric(4, 3) not null default 0.700 check (minimum_pose_confidence between 0 and 1),
  down_elbow_angle_degrees numeric(5, 2) not null default 90 check (down_elbow_angle_degrees between 30 and 120),
  up_elbow_angle_degrees numeric(5, 2) not null default 160 check (up_elbow_angle_degrees between 120 and 180),
  minimum_body_angle_degrees numeric(5, 2) not null default 150 check (minimum_body_angle_degrees between 90 and 180),
  minimum_rep_duration_seconds numeric(5, 2) not null default 0.35 check (minimum_rep_duration_seconds between 0.1 and 10),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (down_elbow_angle_degrees < up_elbow_angle_degrees)
);

insert into public.exercise_configuration (id) values (true);

create table public.exercise_challenges (
  target_reps smallint primary key check (target_reps in (5, 10, 20)),
  reward_seconds integer not null check (reward_seconds between 60 and 86400),
  enabled boolean not null default true,
  display_order smallint not null unique check (display_order between 1 and 3),
  created_at timestamptz not null default now(),
  unique (target_reps, reward_seconds)
);

insert into public.exercise_challenges (target_reps, reward_seconds, display_order)
values (5, 300, 1), (10, 600, 2), (20, 1200, 3);

create table public.exercise_sessions (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  client_request_id uuid not null,
  exercise_type text not null default 'pushup' check (exercise_type = 'pushup'),
  status text not null default 'active' check (status in ('active', 'claimed', 'expired', 'cancelled')),
  target_reps smallint not null references public.exercise_challenges(target_reps) on delete restrict,
  reward_seconds integer not null check (reward_seconds between 60 and 86400),
  app_version text not null check (app_version ~ '^[0-9]{1,9}(\.[0-9]{1,9}){0,2}$'),
  detection_version text not null check (detection_version ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'),
  completed_reps smallint check (completed_reps is null or completed_reps between 0 and 1000),
  duration_seconds numeric(10, 3) check (duration_seconds is null or duration_seconds > 0),
  claim_detection_version text check (claim_detection_version is null or claim_detection_version ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'),
  expires_at timestamptz not null,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, client_request_id),
  check (
    (status = 'claimed' and completed_reps is not null and duration_seconds is not null and claim_detection_version is not null and completed_at is not null)
    or
    (status in ('active', 'expired', 'cancelled') and completed_reps is null and duration_seconds is null and claim_detection_version is null and completed_at is null)
  )
);

create unique index exercise_sessions_one_active_user_idx
  on public.exercise_sessions (user_id) where status = 'active';
create index exercise_sessions_user_created_idx
  on public.exercise_sessions (user_id, created_at desc);
create index exercise_sessions_expiry_idx
  on public.exercise_sessions (expires_at) where status = 'active';
create index exercise_sessions_target_reps_idx
  on public.exercise_sessions (target_reps);

create table public.reward_transactions (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source_type text not null check (source_type ~ '^[a-z][a-z0-9_]{0,63}$'),
  source_id uuid not null,
  amount_seconds integer not null check (amount_seconds > 0 and amount_seconds <= 86400),
  earned_on date not null default ((now() at time zone 'utc')::date),
  created_at timestamptz not null default now(),
  unique (source_type, source_id)
);

create index reward_transactions_user_day_source_idx
  on public.reward_transactions (user_id, earned_on, source_type);

create trigger exercise_configuration_updated_at
before update on public.exercise_configuration
for each row execute function private.set_updated_at();
create trigger exercise_sessions_updated_at
before update on public.exercise_sessions
for each row execute function private.set_updated_at();

alter table public.exercise_configuration enable row level security;
alter table public.exercise_challenges enable row level security;
alter table public.exercise_sessions enable row level security;
alter table public.reward_transactions enable row level security;

revoke all on table public.exercise_configuration from public, anon, authenticated;
revoke all on table public.exercise_challenges from public, anon, authenticated;
revoke all on table public.exercise_sessions from public, anon, authenticated;
revoke all on table public.reward_transactions from public, anon, authenticated;

grant select, insert, update, delete on table public.exercise_configuration to service_role;
grant select, insert, update, delete on table public.exercise_challenges to service_role;
grant select, insert, update, delete on table public.exercise_sessions to service_role;
grant select, insert, update, delete on table public.reward_transactions to service_role;

create function private.version_at_least(candidate text, minimum_version text)
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select
    case when candidate ~ '^[0-9]{1,9}(\.[0-9]{1,9}){0,2}$'
           and minimum_version ~ '^[0-9]{1,9}(\.[0-9]{1,9}){0,2}$'
      then row(
        split_part(candidate, '.', 1)::bigint,
        coalesce(nullif(split_part(candidate, '.', 2), ''), '0')::bigint,
        coalesce(nullif(split_part(candidate, '.', 3), ''), '0')::bigint
      ) >= row(
        split_part(minimum_version, '.', 1)::bigint,
        coalesce(nullif(split_part(minimum_version, '.', 2), ''), '0')::bigint,
        coalesce(nullif(split_part(minimum_version, '.', 3), ''), '0')::bigint
      )
      else false
    end
$$;

create function public.cleanup_expired_exercise_sessions()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected integer;
begin
  update public.exercise_sessions
  set status = 'expired'
  where status = 'active' and expires_at <= now();
  get diagnostics affected = row_count;
  return affected;
end;
$$;

create function public.start_exercise_session(
  p_user_id uuid,
  p_client_request_id uuid,
  p_target_reps integer,
  p_app_version text,
  p_detection_version text
)
returns public.exercise_sessions
language plpgsql
security definer
set search_path = ''
as $$
declare
  config_record public.exercise_configuration;
  challenge_record public.exercise_challenges;
  existing_session public.exercise_sessions;
  new_session public.exercise_sessions;
  earned_seconds integer;
  utc_day date := (now() at time zone 'utc')::date;
begin
  if p_user_id is null or p_client_request_id is null then
    raise exception using errcode = '22004', message = 'user and client request are required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':' || utc_day::text, 0));

  select * into existing_session
  from public.exercise_sessions
  where user_id = p_user_id and client_request_id = p_client_request_id;
  if found then
    return existing_session;
  end if;

  update public.exercise_sessions
  set status = 'expired'
  where user_id = p_user_id and status = 'active' and expires_at <= now();

  if exists (
    select 1 from public.exercise_sessions
    where user_id = p_user_id and status = 'active'
  ) then
    raise exception using errcode = 'P0001', message = 'an exercise session is already active';
  end if;

  select * into config_record
  from public.exercise_configuration
  where id = true and enabled = true;
  if not found then
    raise exception using errcode = 'P0001', message = 'pushups rewards are disabled';
  end if;

  if not private.version_at_least(p_app_version, config_record.minimum_app_version) then
    raise exception using errcode = 'P0001', message = 'minimum app version required';
  end if;
  if p_detection_version is distinct from config_record.detection_version then
    raise exception using errcode = 'P0001', message = 'unsupported detection version';
  end if;

  if config_record.entitlement_required and not exists (
    select 1 from public.user_entitlements
    where user_id = p_user_id
      and entitlement_id = config_record.entitlement_id
      and is_active
      and (expires_at is null or expires_at > now())
  ) then
    raise exception using errcode = '42501', message = 'active entitlement required';
  end if;

  select * into challenge_record
  from public.exercise_challenges
  where target_reps = p_target_reps and enabled;
  if not found then
    raise exception using errcode = '22023', message = 'unsupported pushups challenge';
  end if;

  select coalesce(sum(amount_seconds), 0)::integer into earned_seconds
  from public.reward_transactions
  where user_id = p_user_id and earned_on = utc_day and source_type = 'pushups';
  if config_record.daily_cap_seconds - earned_seconds < challenge_record.reward_seconds then
    raise exception using errcode = 'P0001', message = 'daily pushups reward cap reached';
  end if;

  insert into public.exercise_sessions (
    user_id, client_request_id, target_reps, reward_seconds, app_version,
    detection_version, expires_at
  ) values (
    p_user_id, p_client_request_id, challenge_record.target_reps,
    challenge_record.reward_seconds, p_app_version, p_detection_version,
    now() + make_interval(secs => config_record.session_ttl_seconds)
  ) returning * into new_session;

  return new_session;
end;
$$;

create function public.claim_exercise_reward(
  p_user_id uuid,
  p_session_id uuid,
  p_completed_reps integer,
  p_duration_seconds numeric,
  p_completed_at timestamptz,
  p_detection_version text
)
returns public.reward_transactions
language plpgsql
security definer
set search_path = ''
as $$
declare
  config_record public.exercise_configuration;
  target_session public.exercise_sessions;
  existing_transaction public.reward_transactions;
  new_transaction public.reward_transactions;
  earned_seconds integer;
  utc_day date;
begin
  if p_user_id is null or p_session_id is null then
    raise exception using errcode = '22004', message = 'user and session are required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('exercise-session:' || p_session_id::text, 0));

  select * into existing_transaction
  from public.reward_transactions
  where source_type = 'pushups' and source_id = p_session_id;
  if found then
    if existing_transaction.user_id <> p_user_id then
      raise exception using errcode = '42501', message = 'session ownership mismatch';
    end if;
    return existing_transaction;
  end if;

  if p_completed_at is null then
    raise exception using errcode = '22023', message = 'invalid exercise completion time';
  end if;

  utc_day := (p_completed_at at time zone 'utc')::date;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':' || utc_day::text, 0));

  select * into target_session
  from public.exercise_sessions
  where id = p_session_id and user_id = p_user_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'exercise session not found';
  end if;
  if target_session.status not in ('active', 'expired') then
    raise exception using errcode = 'P0001', message = 'exercise session is not active';
  end if;
  if p_completed_at < target_session.created_at
     or p_completed_at > target_session.expires_at
     or p_completed_at > now() + interval '5 seconds' then
    raise exception using errcode = '22023', message = 'invalid exercise completion time';
  end if;

  select * into config_record
  from public.exercise_configuration
  where id = true and enabled = true;
  if not found then
    raise exception using errcode = 'P0001', message = 'pushups rewards are disabled';
  end if;

  if config_record.entitlement_required and not exists (
    select 1 from public.user_entitlements
    where user_id = p_user_id
      and entitlement_id = config_record.entitlement_id
      and is_active
      and (expires_at is null or expires_at > now())
  ) then
    raise exception using errcode = '42501', message = 'active entitlement required';
  end if;

  if not private.version_at_least(target_session.app_version, config_record.minimum_app_version) then
    raise exception using errcode = 'P0001', message = 'minimum app version required';
  end if;

  if p_detection_version is distinct from target_session.detection_version
     or p_detection_version is distinct from config_record.detection_version then
    raise exception using errcode = '22023', message = 'detection version mismatch';
  end if;
  if p_completed_reps is null or p_completed_reps < target_session.target_reps
     or p_completed_reps > 1000 then
    raise exception using errcode = '22023', message = 'challenge target not completed';
  end if;
  if p_duration_seconds is null
     or p_duration_seconds < target_session.target_reps * config_record.minimum_rep_duration_seconds
     or p_duration_seconds > extract(epoch from (p_completed_at - target_session.created_at)) + 5 then
    raise exception using errcode = '22023', message = 'invalid exercise duration';
  end if;

  select coalesce(sum(amount_seconds), 0)::integer into earned_seconds
  from public.reward_transactions
  where user_id = p_user_id and earned_on = utc_day and source_type = 'pushups';
  if config_record.daily_cap_seconds - earned_seconds < target_session.reward_seconds then
    raise exception using errcode = 'P0001', message = 'daily pushups reward cap reached';
  end if;

  insert into public.reward_transactions (
    user_id, source_type, source_id, amount_seconds, earned_on
  ) values (
    p_user_id, 'pushups', p_session_id, target_session.reward_seconds, utc_day
  ) returning * into new_transaction;

  update public.exercise_sessions
  set status = 'claimed',
      completed_reps = p_completed_reps,
      duration_seconds = p_duration_seconds,
      claim_detection_version = p_detection_version,
      completed_at = p_completed_at
  where id = p_session_id;

  return new_transaction;
end;
$$;

revoke execute on function private.version_at_least(text, text) from public, anon, authenticated, service_role;
revoke all on function public.cleanup_expired_exercise_sessions() from public, anon, authenticated;
revoke all on function public.start_exercise_session(uuid, uuid, integer, text, text) from public, anon, authenticated;
revoke all on function public.claim_exercise_reward(uuid, uuid, integer, numeric, timestamptz, text) from public, anon, authenticated;
grant execute on function public.cleanup_expired_exercise_sessions() to service_role;
grant execute on function public.start_exercise_session(uuid, uuid, integer, text, text) to service_role;
grant execute on function public.claim_exercise_reward(uuid, uuid, integer, numeric, timestamptz, text) to service_role;
