begin;
create extension if not exists pgtap with schema extensions;
select plan(31);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values ('22222222-2222-4222-8222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pushups-test@example.com', '', now(), now());

update public.exercise_configuration
set enabled = true,
    entitlement_required = false,
    minimum_app_version = '2.1.0',
    detection_version = 'pose-v1'
where id = true;

select throws_ok(
  $$select public.start_exercise_session('22222222-2222-4222-8222-222222222222', '10000000-0000-4000-8000-000000000001', 5, '2.0.9', 'pose-v1')$$,
  'P0001',
  'minimum app version required',
  'start enforces the remote minimum app version'
);
select throws_ok(
  $$select public.start_exercise_session('22222222-2222-4222-8222-222222222222', '10000000-0000-4000-8000-000000000001', 5, '2.1', 'pose-v0')$$,
  'P0001',
  'unsupported detection version',
  'start enforces the remote detection version'
);

select is(
  (public.start_exercise_session('22222222-2222-4222-8222-222222222222', '10000000-0000-4000-8000-000000000001', 5, '2.1', 'pose-v1')).target_reps,
  5::smallint,
  'start selects the requested supported challenge'
);
select is(
  (public.start_exercise_session('22222222-2222-4222-8222-222222222222', '10000000-0000-4000-8000-000000000001', 20, '9.9.9', 'different')).reward_seconds,
  300,
  'same client request UUID returns the original server reward'
);
select is(
  (select count(*)::integer from public.exercise_sessions where user_id = '22222222-2222-4222-8222-222222222222'),
  1,
  'idempotent start creates one session'
);
select throws_ok(
  $$select public.start_exercise_session('22222222-2222-4222-8222-222222222222', '10000000-0000-4000-8000-000000000002', 10, '2.1', 'pose-v1')$$,
  'P0001',
  'an exercise session is already active',
  'a user cannot start a second active session'
);
select throws_ok(
  $$select public.claim_exercise_reward('22222222-2222-4222-8222-222222222222', (select id from public.exercise_sessions where client_request_id = '10000000-0000-4000-8000-000000000001'), 4, 2, now(), 'pose-v1')$$,
  '22023',
  'challenge target not completed',
  'claim uses the server-stored repetition target'
);
select throws_ok(
  $$select public.claim_exercise_reward('22222222-2222-4222-8222-222222222222', (select id from public.exercise_sessions where client_request_id = '10000000-0000-4000-8000-000000000001'), 5, 2, now(), 'pose-v2')$$,
  '22023',
  'detection version mismatch',
  'claim requires the session detection version'
);
update public.exercise_sessions set created_at = now() - interval '10 seconds'
where client_request_id = '10000000-0000-4000-8000-000000000001';
select is(
  (public.claim_exercise_reward('22222222-2222-4222-8222-222222222222', (select id from public.exercise_sessions where client_request_id = '10000000-0000-4000-8000-000000000001'), 5, 2, now(), 'pose-v1')).amount_seconds,
  300,
  'first valid claim grants the server-stored reward'
);
select is(
  (select status from public.exercise_sessions where client_request_id = '10000000-0000-4000-8000-000000000001'),
  'claimed',
  'successful claim closes the session'
);
select is(
  (select completed_reps from public.exercise_sessions where client_request_id = '10000000-0000-4000-8000-000000000001'),
  5::smallint,
  'claim persists only completion telemetry'
);
select is(
  (public.claim_exercise_reward('22222222-2222-4222-8222-222222222222', (select id from public.exercise_sessions where client_request_id = '10000000-0000-4000-8000-000000000001'), 0, 0, now(), 'invalid')).amount_seconds,
  300,
  'repeated claim returns the same receipt before revalidating telemetry'
);
select is(
  (select count(*)::integer from public.reward_transactions where source_type = 'pushups' and source_id = (select id from public.exercise_sessions where client_request_id = '10000000-0000-4000-8000-000000000001')),
  1,
  'idempotent claim creates one reward transaction'
);

select is(
  (public.start_exercise_session('22222222-2222-4222-8222-222222222222', '10000000-0000-4000-8000-000000000002', 20, '2.1.0', 'pose-v1')).target_reps,
  20::smallint,
  'twenty-rep challenge starts after the first claim'
);
update public.exercise_sessions set created_at = now() - interval '30 seconds'
where client_request_id = '10000000-0000-4000-8000-000000000002';
select is(
  (public.claim_exercise_reward('22222222-2222-4222-8222-222222222222', (select id from public.exercise_sessions where client_request_id = '10000000-0000-4000-8000-000000000002'), 21, 10, now(), 'pose-v1')).amount_seconds,
  1200,
  'claim accepts extra detected reps but grants only the server reward'
);
select is(
  (select sum(amount_seconds)::integer from public.reward_transactions where user_id = '22222222-2222-4222-8222-222222222222' and source_type = 'pushups'),
  1500,
  'UTC-day rewards total twenty-five minutes'
);
select is(
  (public.start_exercise_session('22222222-2222-4222-8222-222222222222', '10000000-0000-4000-8000-000000000003', 5, '2.1.0', 'pose-v1')).reward_seconds,
  300,
  'a challenge can start when its full reward currently fits'
);
insert into public.reward_transactions (user_id, source_type, source_id, amount_seconds)
values ('22222222-2222-4222-8222-222222222222', 'pushups', '30000000-0000-4000-8000-000000000001', 300);
update public.exercise_sessions set created_at = now() - interval '10 seconds'
where client_request_id = '10000000-0000-4000-8000-000000000003';
select throws_ok(
  $$select public.claim_exercise_reward('22222222-2222-4222-8222-222222222222', (select id from public.exercise_sessions where client_request_id = '10000000-0000-4000-8000-000000000003'), 5, 2, now(), 'pose-v1')$$,
  'P0001',
  'daily pushups reward cap reached',
  'claim rejects a reward that no longer fits under the cap'
);
select is(
  (select sum(amount_seconds)::integer from public.reward_transactions where user_id = '22222222-2222-4222-8222-222222222222' and source_type = 'pushups'),
  1800,
  'failed claim never grants a partial reward'
);
select is(
  (select count(*)::integer from public.reward_transactions where source_id = (select id from public.exercise_sessions where client_request_id = '10000000-0000-4000-8000-000000000003')),
  0,
  'failed claim creates no receipt'
);
select is(
  (select status from public.exercise_sessions where client_request_id = '10000000-0000-4000-8000-000000000003'),
  'active',
  'failed claim leaves the session active'
);
update public.exercise_sessions set expires_at = now() - interval '1 second'
where client_request_id = '10000000-0000-4000-8000-000000000003';
select is(public.cleanup_expired_exercise_sessions(), 1, 'expiry cleanup closes active expired sessions');
select is(
  (select status from public.exercise_sessions where client_request_id = '10000000-0000-4000-8000-000000000003'),
  'expired',
  'cleanup records expiration without completion telemetry'
);

delete from public.reward_transactions where source_id = '30000000-0000-4000-8000-000000000001';
select is(
  (public.start_exercise_session('22222222-2222-4222-8222-222222222222', '10000000-0000-4000-8000-000000000004', 5, '2.1.0', 'pose-v1')).target_reps,
  5::smallint,
  'a replacement can start after expiry'
);
update public.exercise_sessions
set expires_at = now() - interval '1 day 1 second', created_at = now() - interval '1 day 10 seconds'
where client_request_id = '10000000-0000-4000-8000-000000000004';
select is(
  (public.claim_exercise_reward('22222222-2222-4222-8222-222222222222', (select id from public.exercise_sessions where client_request_id = '10000000-0000-4000-8000-000000000004'), 5, 2, now() - interval '1 day 2 seconds', 'pose-v1')).amount_seconds,
  300,
  'an offline completion can claim after expiry when completed_at is inside the session window'
);
select is(
  (select earned_on from public.reward_transactions where source_id = (select id from public.exercise_sessions where client_request_id = '10000000-0000-4000-8000-000000000004')),
  ((now() at time zone 'utc')::date - 1),
  'delayed claim counts against the UTC completion day'
);
select is(
  (select status from public.exercise_sessions where client_request_id = '10000000-0000-4000-8000-000000000004'),
  'claimed',
  'a valid delayed claim atomically closes the expired session'
);
update public.exercise_configuration set entitlement_required = true where id = true;
select throws_ok(
  $$select public.start_exercise_session('22222222-2222-4222-8222-222222222222', '10000000-0000-4000-8000-000000000005', 5, '2.1.0', 'pose-v1')$$,
  '42501',
  'active entitlement required',
  'start rechecks the canonical Pro entitlement'
);

update public.exercise_configuration
set entitlement_required = false, daily_cap_seconds = 2400
where id = true;
update public.exercise_challenges set reward_seconds = 360 where target_reps = 5;
select is(
  (select daily_cap_seconds from public.exercise_configuration where id = true),
  2400,
  'daily cap can be configured within its constraint'
);
select is(
  (public.start_exercise_session('22222222-2222-4222-8222-222222222222', '10000000-0000-4000-8000-000000000005', 5, '2.1.0', 'pose-v1')).reward_seconds,
  360,
  'start snapshots a configured challenge reward'
);
update public.exercise_sessions set created_at = now() - interval '10 seconds'
where client_request_id = '10000000-0000-4000-8000-000000000005';
select is(
  (public.claim_exercise_reward('22222222-2222-4222-8222-222222222222', (select id from public.exercise_sessions where client_request_id = '10000000-0000-4000-8000-000000000005'), 5, 2, now(), 'pose-v1')).amount_seconds,
  360,
  'claim grants the configured server-side reward under the configured cap'
);

select * from finish();
rollback;
