begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values ('11111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'study-test@example.com', '', now(), now());

update public.study_configuration set reward_seconds = 300, daily_cap_seconds = 500, entitlement_required = false where id = true;
insert into public.study_sessions (id, user_id, client_request_id, source_text, locale, question, reference_answer, evaluation_criteria, generation_confidence, reward_seconds, expires_at)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', '11111111-1111-4111-8111-111111111111', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1', 'OCR source one', 'en', 'Q1', 'A1', 'R1', 0.9, 300, now() + interval '10 minutes');

select is((public.grant_study_reward('11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', 0::smallint)).amount_seconds, 300, 'first pass grants configured reward');
select is((public.grant_study_reward('11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', 0::smallint)).amount_seconds, 300, 'same session is idempotent');
select is((select count(*)::integer from public.study_reward_transactions where session_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'), 1, 'idempotency creates one transaction');
insert into public.study_sessions (id, user_id, client_request_id, source_text, locale, question, reference_answer, evaluation_criteria, generation_confidence, reward_seconds, expires_at)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', '11111111-1111-4111-8111-111111111111', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2', 'OCR source two', 'en', 'Q2', 'A2', 'R2', 0.9, 300, now() + interval '10 minutes');
select throws_ok(
  $$select public.grant_study_reward('11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', 0::smallint)$$,
  'P0001',
  'daily study reward cap reached',
  'reward is rejected rather than partially clipped'
);
select is((select sum(amount_seconds)::integer from public.study_reward_transactions where user_id = '11111111-1111-4111-8111-111111111111'), 300, 'rejected reward leaves daily total unchanged');
select is((select status from public.study_sessions where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'), 'passed', 'pass marks session complete');
select is((select source_text from public.study_sessions where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'), null, 'pass clears OCR source');
select is((select reference_answer from public.study_sessions where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'), null, 'pass clears reference answer');
select is((select evaluation_criteria from public.study_sessions where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'), null, 'pass clears evaluation criteria');
update public.study_sessions set expires_at = now() - interval '1 second' where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2';
select is(public.cleanup_expired_study_sessions(), 1, 'expiry cleanup closes the remaining active session');
select is((select source_text from public.study_sessions where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2'), null, 'expiry cleanup clears OCR source');
insert into public.study_sessions (id, user_id, client_request_id, source_text, locale, question, reference_answer, evaluation_criteria, generation_confidence, reward_seconds, expires_at)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3', '11111111-1111-4111-8111-111111111111', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3', 'OCR source three', 'en', 'Q3', 'A3', 'R3', 0.9, 300, now() + interval '10 minutes');
select throws_ok(
  $$update public.study_sessions set status = 'abandoned', completed_at = now() where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3'$$,
  '23514',
  null,
  'terminal session cannot retain sensitive material'
);
update public.study_sessions
set status = 'abandoned', source_text = null, reference_answer = null, evaluation_criteria = null, completed_at = now()
where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3';
select is((select status from public.study_sessions where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3'), 'abandoned', 'abandon closes session');
select is((select source_text from public.study_sessions where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3'), null, 'abandon clears OCR source');
insert into public.study_sessions (id, user_id, client_request_id, source_text, locale, question, reference_answer, evaluation_criteria, generation_confidence, reward_seconds, expires_at)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', '11111111-1111-4111-8111-111111111111', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4', 'OCR source four', 'en', 'Q4', 'A4', 'R4', 0.9, 300, now() + interval '10 minutes');
select throws_ok(
  $$select public.prepare_study_generation('11111111-1111-4111-8111-111111111111', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb5', null, true)$$,
  'P0001',
  'daily study reward cap reached',
  'generation preflight rejects insufficient full reward capacity'
);
select is((select status from public.study_sessions where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'), 'active', 'failed preflight does not abandon current session');
update public.study_configuration set daily_cap_seconds = 1000 where id = true;
select is(public.prepare_study_generation('11111111-1111-4111-8111-111111111111', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb5', null, true), true, 'new request passes generation preflight');
select is((select status from public.study_sessions where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'), 'abandoned', 'new request abandons unrelated active session');
select is((select source_text from public.study_sessions where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'), null, 'superseded session source is cleared');
insert into public.study_sessions (id, user_id, client_request_id, source_text, locale, question, reference_answer, evaluation_criteria, generation_confidence, reward_seconds, expires_at)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5', '11111111-1111-4111-8111-111111111111', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb5', 'OCR source five', 'en', 'Q5', 'A5', 'R5', 0.9, 300, now() + interval '10 minutes');
select is(public.prepare_study_generation('11111111-1111-4111-8111-111111111111', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb5', null, true), false, 'same request ID remains idempotent');

select * from finish();
rollback;
