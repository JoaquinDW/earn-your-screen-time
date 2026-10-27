begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('77777777-7777-4777-8777-777777777771', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ana@example.com', '', now(), now()),
  ('77777777-7777-4777-8777-777777777772', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ben@example.com', '', now(), now()),
  ('77777777-7777-4777-8777-777777777773', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cleo@example.com', '', now(), now());

select is(
  (public.social_upsert_profile('77777777-7777-4777-8777-777777777771', ' Ana ')).display_name,
  'Ana',
  'a profile keeps a trimmed name'
);
select matches(
  (select invite_code from public.social_profiles where user_id = '77777777-7777-4777-8777-777777777771'),
  '^[A-HJ-NP-Z2-9]{6}$',
  'a profile gets a six-character invite code'
);
select public.social_upsert_profile('77777777-7777-4777-8777-777777777772', 'Ben');

select throws_ok(
  $$select public.social_add_friend('77777777-7777-4777-8777-777777777773', (select invite_code from public.social_profiles where user_id = '77777777-7777-4777-8777-777777777771'), current_date)$$,
  'P0002', 'social profile required',
  'someone without a profile cannot add friends'
);
select throws_ok(
  $$select public.social_add_friend('77777777-7777-4777-8777-777777777771', (select invite_code from public.social_profiles where user_id = '77777777-7777-4777-8777-777777777771'), current_date)$$,
  '22023', 'cannot add yourself',
  'your own code is refused'
);
select is(
  (public.social_add_friend('77777777-7777-4777-8777-777777777771', lower((select invite_code from public.social_profiles where user_id = '77777777-7777-4777-8777-777777777772')), current_date)).display_name,
  'Ben',
  'a friend is added by code, in any case'
);
select lives_ok(
  $$select public.social_add_friend('77777777-7777-4777-8777-777777777771', (select invite_code from public.social_profiles where user_id = '77777777-7777-4777-8777-777777777772'), current_date)$$,
  'adding the same friend twice is not an error'
);
select is(
  (select count(*)::integer from public.social_events where recipient_id = '77777777-7777-4777-8777-777777777772' and kind = 'friend_added'),
  1,
  'the new friend hears about it once'
);

select is_empty(
  $$select * from public.social_record_progress('77777777-7777-4777-8777-777777777771', current_date, 8000, 3000, 300, 2, false)$$,
  'a day in progress tells nobody'
);
select results_eq(
  $$select * from public.social_record_progress('77777777-7777-4777-8777-777777777771', current_date - 1, 8000, 3000, 300, 2, true)$$,
  $$values ('77777777-7777-4777-8777-777777777772'::uuid)$$,
  'a finished day short of its goal is reported to friends'
);
select is_empty(
  $$select * from public.social_record_progress('77777777-7777-4777-8777-777777777771', current_date - 1, 8000, 3000, 300, 2, true)$$,
  'a miss is reported only once'
);
select throws_ok(
  $$select public.social_record_progress('77777777-7777-4777-8777-777777777771', current_date - 30, 8000, 3000, 300, 2, true)$$,
  '22023', 'day out of range',
  'old days cannot be rewritten'
);

select ok(
  public.social_send('77777777-7777-4777-8777-777777777772', '77777777-7777-4777-8777-777777777771', 'nudge', current_date),
  'a friend can nudge'
);
select ok(
  not public.social_send('77777777-7777-4777-8777-777777777772', '77777777-7777-4777-8777-777777777771', 'nudge', current_date),
  'but only once a day'
);

select public.social_join_squad(
  '77777777-7777-4777-8777-777777777772',
  (public.social_create_squad('77777777-7777-4777-8777-777777777771', 'Morning crew')).invite_code
);
select results_eq(
  $$select display_name, goal_days, earned_seconds from public.social_squad_standings('77777777-7777-4777-8777-777777777771', (select id from public.squads where name = 'Morning crew'), current_date - 6)$$,
  $$values ('Ana'::text, 0, 600), ('Ben'::text, 0, 0)$$,
  'the league ranks members by days on goal, then minutes'
);

select * from finish();
rollback;
