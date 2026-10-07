-- Push-ups for people who have not paid yet: one reward, once per account.
--
-- The paywall now follows the first unlock instead of ending onboarding, so a free user has to
-- be able to earn that unlock. Walking already can; this lets push-ups do it too, exactly
-- `free_rewards_per_user` times across the account's whole history (not per day). After that,
-- or with the setting at 0, the Pro entitlement is required again as before.
--
-- The count is taken from `reward_transactions`, which is written only by a successful claim,
-- so an abandoned or failed session never uses up the free reward. Idempotent retries of the
-- free claim still return their original receipt: that check runs before access is evaluated.

alter table public.exercise_configuration
  add column free_rewards_per_user smallint not null default 1
    check (free_rewards_per_user between 0 and 10);

create function private.exercise_reward_allowed(
  p_user_id uuid,
  p_config public.exercise_configuration
)
returns boolean
language sql
stable
set search_path = ''
as $$
  select not p_config.entitlement_required
    or exists (
      select 1 from public.user_entitlements
      where user_id = p_user_id
        and entitlement_id = p_config.entitlement_id
        and is_active
        and (expires_at is null or expires_at > now())
    )
    or (
      select count(*) from public.reward_transactions
      where user_id = p_user_id and source_type = 'pushups'
    ) < p_config.free_rewards_per_user
$$;

revoke execute on function private.exercise_reward_allowed(uuid, public.exercise_configuration)
  from public, anon, authenticated;

create or replace function public.start_exercise_session(
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

  if not private.exercise_reward_allowed(p_user_id, config_record) then
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

create or replace function public.claim_exercise_reward(
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

  if not private.exercise_reward_allowed(p_user_id, config_record) then
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
