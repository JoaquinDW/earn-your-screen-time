-- Squats as a second camera exercise, rewarded through the same sessions and claims as push-ups.
--
-- A squat is easier than a push-up, so its challenges ask for twice the repetitions for the
-- same minutes. Both exercises share one daily cap and one free reward: the cap limits camera
-- earning as a whole, and the free reward exists to let someone who has not paid earn a first
-- unlock, not one per exercise.
--
-- Push-up behaviour is unchanged. Older clients never send an exercise type and keep starting
-- push-up sessions; the RPC error messages they map on are kept word for word.

alter table public.exercise_configuration
  add column squat_enabled boolean not null default true,
  add column squat_minimum_pose_confidence numeric(4, 3) not null default 0.400
    check (squat_minimum_pose_confidence between 0 and 1),
  add column squat_bottom_depth_score numeric(4, 3) not null default 0.500
    check (squat_bottom_depth_score between 0.2 and 0.95),
  add column squat_minimum_rep_duration_seconds numeric(5, 2) not null default 0.60
    check (squat_minimum_rep_duration_seconds between 0.1 and 10);

-- Challenges become per exercise: the repetition count alone no longer identifies one.
alter table public.exercise_sessions drop constraint exercise_sessions_target_reps_fkey;
drop index public.exercise_sessions_target_reps_idx;

alter table public.exercise_challenges
  add column exercise_type text not null default 'pushup'
    check (exercise_type in ('pushup', 'squat'));
alter table public.exercise_challenges drop constraint exercise_challenges_pkey;
alter table public.exercise_challenges drop constraint exercise_challenges_target_reps_check;
alter table public.exercise_challenges drop constraint exercise_challenges_display_order_key;
alter table public.exercise_challenges drop constraint exercise_challenges_target_reps_reward_seconds_key;
alter table public.exercise_challenges
  add primary key (exercise_type, target_reps),
  add constraint exercise_challenges_target_reps_check check (target_reps between 1 and 100),
  add constraint exercise_challenges_display_order_key unique (exercise_type, display_order);

insert into public.exercise_challenges (exercise_type, target_reps, reward_seconds, display_order)
values ('squat', 10, 300, 1), ('squat', 20, 600, 2), ('squat', 40, 1200, 3);

alter table public.exercise_sessions drop constraint exercise_sessions_exercise_type_check;
alter table public.exercise_sessions
  add constraint exercise_sessions_exercise_type_check check (exercise_type in ('pushup', 'squat')),
  add constraint exercise_sessions_challenge_fkey foreign key (exercise_type, target_reps)
    references public.exercise_challenges (exercise_type, target_reps) on delete restrict;
create index exercise_sessions_challenge_idx
  on public.exercise_sessions (exercise_type, target_reps);

create function private.exercise_reward_source(p_exercise_type text)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select case p_exercise_type when 'squat' then 'squats' else 'pushups' end
$$;

revoke execute on function private.exercise_reward_source(text) from public, anon, authenticated;

create or replace function private.exercise_reward_allowed(
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
      where user_id = p_user_id and source_type in ('pushups', 'squats')
    ) < p_config.free_rewards_per_user
$$;

drop function public.start_exercise_session(uuid, uuid, integer, text, text);

create function public.start_exercise_session(
  p_user_id uuid,
  p_client_request_id uuid,
  p_target_reps integer,
  p_app_version text,
  p_detection_version text,
  p_exercise_type text default 'pushup'
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
  if p_exercise_type is null or p_exercise_type not in ('pushup', 'squat') then
    raise exception using errcode = '22023', message = 'unsupported exercise type';
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
  if p_exercise_type = 'squat' and not config_record.squat_enabled then
    raise exception using errcode = 'P0001', message = 'squats rewards are disabled';
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
  where exercise_type = p_exercise_type and target_reps = p_target_reps and enabled;
  if not found then
    raise exception using errcode = '22023', message = 'unsupported pushups challenge';
  end if;

  select coalesce(sum(amount_seconds), 0)::integer into earned_seconds
  from public.reward_transactions
  where user_id = p_user_id and earned_on = utc_day and source_type in ('pushups', 'squats');
  if config_record.daily_cap_seconds - earned_seconds < challenge_record.reward_seconds then
    raise exception using errcode = 'P0001', message = 'daily pushups reward cap reached';
  end if;

  insert into public.exercise_sessions (
    user_id, client_request_id, exercise_type, target_reps, reward_seconds, app_version,
    detection_version, expires_at
  ) values (
    p_user_id, p_client_request_id, p_exercise_type, challenge_record.target_reps,
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
  minimum_rep_duration numeric;
  utc_day date;
begin
  if p_user_id is null or p_session_id is null then
    raise exception using errcode = '22004', message = 'user and session are required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('exercise-session:' || p_session_id::text, 0));

  select * into existing_transaction
  from public.reward_transactions
  where source_type in ('pushups', 'squats') and source_id = p_session_id;
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
  if target_session.exercise_type = 'squat' and not config_record.squat_enabled then
    raise exception using errcode = 'P0001', message = 'squats rewards are disabled';
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
  minimum_rep_duration := case target_session.exercise_type
    when 'squat' then config_record.squat_minimum_rep_duration_seconds
    else config_record.minimum_rep_duration_seconds
  end;
  if p_duration_seconds is null
     or p_duration_seconds < target_session.target_reps * minimum_rep_duration
     or p_duration_seconds > extract(epoch from (p_completed_at - target_session.created_at)) + 5 then
    raise exception using errcode = '22023', message = 'invalid exercise duration';
  end if;

  select coalesce(sum(amount_seconds), 0)::integer into earned_seconds
  from public.reward_transactions
  where user_id = p_user_id and earned_on = utc_day and source_type in ('pushups', 'squats');
  if config_record.daily_cap_seconds - earned_seconds < target_session.reward_seconds then
    raise exception using errcode = 'P0001', message = 'daily pushups reward cap reached';
  end if;

  insert into public.reward_transactions (
    user_id, source_type, source_id, amount_seconds, earned_on
  ) values (
    p_user_id, private.exercise_reward_source(target_session.exercise_type), p_session_id,
    target_session.reward_seconds, utc_day
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

revoke all on function public.start_exercise_session(uuid, uuid, integer, text, text, text)
  from public, anon, authenticated;
grant execute on function public.start_exercise_session(uuid, uuid, integer, text, text, text)
  to service_role;
