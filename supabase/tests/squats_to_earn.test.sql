begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('55555555-5555-4555-8555-555555555551', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'squats-1@example.com', '', now(), now()),
  ('55555555-5555-4555-8555-555555555552', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'squats-free@example.com', '', now(), now());

update public.exercise_configuration
set enabled = true,
    squat_enabled = true,
    entitlement_required = false,
    minimum_app_version = '1.0.0',
    detection_version = 'pose-v1',
    minimum_rep_duration_seconds = 0.35,
    squat_minimum_rep_duration_seconds = 0.6
where id = true;

-- Starting
select is(
  (public.start_exercise_session('55555555-5555-4555-8555-555555555551', '70000000-0000-4000-8000-000000000001', 10, '1.3.0', 'pose-v1', 'squat')).exercise_type,
  'squat',
  'a squat session records its exercise'
);
select is(
  (select reward_seconds from public.exercise_sessions where client_request_id = '70000000-0000-4000-8000-000000000001'),
  300,
  'ten squats are worth five minutes'
);
update public.exercise_sessions set status = 'cancelled'
where client_request_id = '70000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.start_exercise_session('55555555-5555-4555-8555-555555555551', '70000000-0000-4000-8000-000000000002', 5, '1.3.0', 'pose-v1', 'squat')$$,
  '22023',
  'unsupported pushups challenge',
  'a push-up repetition count is not a squat challenge'
);
select throws_ok(
  $$select public.start_exercise_session('55555555-5555-4555-8555-555555555551', '70000000-0000-4000-8000-000000000003', 10, '1.3.0', 'pose-v1', 'burpee')$$,
  '22023',
  'unsupported exercise type',
  'unknown exercises are refused'
);
select is(
  (public.start_exercise_session('55555555-5555-4555-8555-555555555551', '70000000-0000-4000-8000-000000000004', 5, '1.3.0', 'pose-v1')).exercise_type,
  'pushup',
  'a client that sends no exercise still starts push-ups'
);
update public.exercise_sessions set status = 'cancelled'
where client_request_id = '70000000-0000-4000-8000-000000000004';

-- Claiming
select lives_ok(
  $$select public.start_exercise_session('55555555-5555-4555-8555-555555555551', '70000000-0000-4000-8000-000000000005', 10, '1.3.0', 'pose-v1', 'squat')$$,
  'a second squat session starts once the first is closed'
);
update public.exercise_sessions set created_at = now() - interval '30 seconds'
where client_request_id = '70000000-0000-4000-8000-000000000005';
select throws_ok(
  $$select public.claim_exercise_reward('55555555-5555-4555-8555-555555555551', (select id from public.exercise_sessions where client_request_id = '70000000-0000-4000-8000-000000000005'), 10, 5, now(), 'pose-v1')$$,
  '22023',
  'invalid exercise duration',
  'squats are held to their own, slower minimum repetition time'
);
select is(
  (public.claim_exercise_reward('55555555-5555-4555-8555-555555555551', (select id from public.exercise_sessions where client_request_id = '70000000-0000-4000-8000-000000000005'), 10, 12, now(), 'pose-v1')).source_type,
  'squats',
  'a squat reward is filed under its own source'
);
select is(
  (public.claim_exercise_reward('55555555-5555-4555-8555-555555555551', (select id from public.exercise_sessions where client_request_id = '70000000-0000-4000-8000-000000000005'), 10, 12, now(), 'pose-v1')).amount_seconds,
  300,
  'retrying a squat claim returns the original receipt'
);
select is(
  (select count(*)::integer from public.reward_transactions where source_id = (select id from public.exercise_sessions where client_request_id = '70000000-0000-4000-8000-000000000005')),
  1,
  'the retry did not pay twice'
);

-- One daily cap across both exercises: 300 from squats + 1200 from push-ups leaves 300.
insert into public.reward_transactions (user_id, source_type, source_id, amount_seconds)
values ('55555555-5555-4555-8555-555555555551', 'pushups', '80000000-0000-4000-8000-000000000001', 1200);
select throws_ok(
  $$select public.start_exercise_session('55555555-5555-4555-8555-555555555551', '70000000-0000-4000-8000-000000000006', 20, '1.3.0', 'pose-v1', 'squat')$$,
  'P0001',
  'daily pushups reward cap reached',
  'squat and push-up minutes share the daily cap'
);
select lives_ok(
  $$select public.start_exercise_session('55555555-5555-4555-8555-555555555551', '70000000-0000-4000-8000-000000000007', 10, '1.3.0', 'pose-v1', 'squat')$$,
  'a challenge that still fits under the shared cap starts'
);
update public.exercise_sessions set status = 'cancelled'
where client_request_id = '70000000-0000-4000-8000-000000000007';

-- Squats can be switched off on their own.
update public.exercise_configuration set squat_enabled = false where id = true;
select throws_ok(
  $$select public.start_exercise_session('55555555-5555-4555-8555-555555555551', '70000000-0000-4000-8000-000000000008', 10, '1.3.0', 'pose-v1', 'squat')$$,
  'P0001',
  'squats rewards are disabled',
  'disabling squats stops new squat sessions'
);
update public.exercise_configuration set squat_enabled = true where id = true;

-- One free reward across both exercises.
update public.exercise_configuration
set entitlement_required = true, free_rewards_per_user = 1
where id = true;
select lives_ok(
  $$select public.start_exercise_session('55555555-5555-4555-8555-555555555552', '70000000-0000-4000-8000-000000000009', 10, '1.3.0', 'pose-v1', 'squat')$$,
  'a user who has not paid can start a free squat challenge'
);
update public.exercise_sessions set created_at = now() - interval '30 seconds'
where client_request_id = '70000000-0000-4000-8000-000000000009';
select is(
  (public.claim_exercise_reward('55555555-5555-4555-8555-555555555552', (select id from public.exercise_sessions where client_request_id = '70000000-0000-4000-8000-000000000009'), 10, 12, now(), 'pose-v1')).amount_seconds,
  300,
  'the free squat reward is granted'
);
select throws_ok(
  $$select public.start_exercise_session('55555555-5555-4555-8555-555555555552', '70000000-0000-4000-8000-000000000010', 5, '1.3.0', 'pose-v1')$$,
  '42501',
  'active entitlement required',
  'the free squat reward also uses up the free push-up reward'
);

select * from finish();
rollback;
