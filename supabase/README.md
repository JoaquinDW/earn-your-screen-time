# Earnit Supabase backend

This directory is a service-owned backend for Study to Earn and Pushups to Earn. Mobile clients authenticate with Supabase Auth, including anonymous Supabase users, and invoke Edge Functions; they receive no direct table or privileged-function authority.

## Setup

1. Install Docker and the Supabase CLI locally, then run `supabase start` from the repository root.
2. Copy `supabase/functions/.env.example` to `supabase/functions/.env` and replace placeholders. Never commit that file.
3. Set `REVENUECAT_ENTITLEMENT_ID` to the RevenueCat entitlement identifier. It defaults to `Earn your Screen Time Pro` to match the current app.
4. Set a RevenueCat secret REST API v1 key with read access. This lets user calls and webhooks refresh canonical subscriber state; without it, webhook payload fields are used where possible and existing cached state is the user-call fallback.
5. Enable HMAC signing on the RevenueCat webhook integration and set its one-time signing secret as `REVENUECAT_WEBHOOK_SECRET`.
6. Configure the webhook URL as `https://<project-ref>.supabase.co/functions/v1/revenuecat-webhook`. JWT verification is intentionally disabled only for this function; every request is authenticated with RevenueCat's raw-body HMAC signature.
7. Apply locally with `supabase db reset`, then serve functions with `supabase functions serve --env-file supabase/functions/.env`.

For hosted secrets, use the Dashboard or `supabase secrets set --env-file supabase/functions/.env`. Supabase injects `SUPABASE_URL` and hosted publishable/secret keys automatically. Prefer current publishable and secret keys; the helpers also accept the CLI's local single-key variables.

## API

Send `Authorization: Bearer <user-access-token>` on all user endpoints.

- `GET /functions/v1/study-config` returns client-safe operational configuration, entitlement status, and UTC-day reward availability.
- `POST /functions/v1/study-session` accepts `{ "action": "start", "client_request_id": "<uuid>", "source_text": "<OCR text>", "locale": "en" }`, `{ "action": "regenerate", "session_id": "<uuid>" }`, or `{ "action": "abandon", "session_id": "<uuid>" }`.
- `POST /functions/v1/study-answer` accepts `{ "session_id": "<uuid>", "answer": "..." }`.
- `GET /functions/v1/pushups-config?app_version=1.0.0` returns the remote feature flag, minimum versions, pose thresholds, available 5/10/20-rep challenges, Pro status, and UTC-day availability.
- `POST /functions/v1/pushups-start` accepts `{ "client_request_id": "<uuid>", "target_reps": 5, "app_version": "1.0.0", "detection_version": "1" }`.
- `POST /functions/v1/pushups-claim` accepts `{ "session_id": "<uuid>", "completed_reps": 5, "duration_seconds": 4.2, "completed_at": "<ISO-8601>", "detection_version": "1" }`. A locally completed claim remains retryable after the session expires when `completed_at` falls inside the original session window.
- `POST /functions/v1/revenuecat-webhook` is reserved for RevenueCat.

Pushups starts enabled with minimum app version `0.1.0` and can be disabled through `exercise_configuration.enabled`; keep its `entitlement_id` aligned with `REVENUECAT_ENTITLEMENT_ID`. Start is idempotent per user and `client_request_id`; it rejects another live session and snapshots the server-selected target, reward, app version, and detection version. The initial challenges are 5/10/20 repetitions for 5/10/20 minutes; enablement, rewards, cap, versions, TTL, and pose thresholds can be changed remotely. Claim accepts only aggregate repetitions, duration, completion time, and detection version; frames and landmarks are rejected and never stored. PostgreSQL serializes claims per session and per user/UTC completion day, rechecks the Pro entitlement, feature flag, target, detection version, completion window, and daily cap, and grants no partial reward. A repeated successful claim returns the original `reward_transactions` receipt, and a locally completed claim can be retried after connectivity returns without moving its reward into a later UTC cap bucket.

`client_request_id` makes only the same start request safe to retry. A different request ID never resumes an existing question: its transactional preflight abandons the prior active session and clears its OCR source, reference answer, and criteria before generating from the new scan. Start validates trimmed OCR text against the configured minimum and maximum length and validates `locale` as a BCP 47 language tag. Generation may use only that text. Regeneration uses the stored source and allows at most one alternative by default. Both start and regeneration recheck enabled state, cached entitlement, and capacity for the full reward before OpenAI is called. Reward grants are separately idempotent by session and serialized per user/UTC day inside PostgreSQL. A reward is all-or-nothing: PostgreSQL rejects it when the full session reward would exceed the remaining daily allowance.

### Response DTOs

`study-config` returns:

```json
{
  "configuration": {
    "enabled": true,
    "entitlement_required": true,
    "questions_per_session": 1,
    "passing_score": 1,
    "reward_seconds": 900,
    "daily_cap_seconds": 1800,
    "session_ttl_seconds": 900,
    "max_regenerations": 1,
    "source_text_min_length": 80,
    "source_text_max_length": 12000,
    "confidence_threshold": 0.7,
    "difficulty": "medium"
  },
  "entitled": true,
  "availability": {
    "completionsToday": 1,
    "earnedSeconds": 900,
    "rewardSecondsRemaining": 900,
    "canEarnFullReward": true,
    "nextAvailableAt": null,
    "resetsAt": "2026-09-13T00:00:00.000Z"
  }
}
```

Successful start/regenerate returns `{ "session": { "id", "status", "question", "expires_at", "regeneration_count", "answer_attempt_count" } }`; start uses HTTP 201 for a new row and may return `idempotent: true` only when that exact `client_request_id` already exists. It never returns an unrelated active session. Source text, reference answers, criteria, prompts, and confidence internals are never returned.

`study-answer` returns `{ "pass": false, "confidence": 0.82, "feedback": "...", "missingConcept": "..." }` for an unsuccessful evaluation. `missingConcept` is either a string or `null`. A pass returns the same evaluation fields plus `reward: { "id", "session_id", "amount_seconds", "earned_on", "created_at" }`. An idempotent retry after a completed pass returns `{ "pass": true, "reward": { ... }, "idempotent": true }` because evaluation feedback is not persisted.

Unusable, unsupported, or below-threshold OCR produces HTTP 422 with `{ "error", "code" }` and does not create or replace a session question. Invalid source length or locale produces HTTP 400.

Keep `study_configuration.entitlement_id` aligned with `REVENUECAT_ENTITLEMENT_ID`. The reward transaction rechecks the cached entitlement and its expiry inside the same database transaction, after the Edge Function has attempted a RevenueCat refresh.

## Data lifecycle

Learner answers are never inserted into PostgreSQL and must not be logged. Active sessions temporarily retain OCR source text, the generated reference answer, and evaluation criteria. Passing, abandoning, and expiry null all three fields. Invoke `public.cleanup_expired_study_sessions()` from a service context periodically (for example, Supabase Cron every five minutes) in addition to the cleanup performed at the start of user requests:

```sql
select public.cleanup_expired_study_sessions();
```

Do not expose that function to clients. The migration grants it only to `service_role`.

## Verification

With the CLI and local stack available:

```sh
supabase db reset
supabase test db
deno test --allow-env supabase/functions/tests
deno check supabase/functions/study-config/index.ts
deno check supabase/functions/study-session/index.ts
deno check supabase/functions/study-answer/index.ts
deno check supabase/functions/revenuecat-webhook/index.ts
deno check supabase/functions/pushups-config/index.ts
deno check supabase/functions/pushups-start/index.ts
deno check supabase/functions/pushups-claim/index.ts
supabase db lint --local
```

The pgTAP suite checks both features' RLS/grants, defaults, all-or-nothing cap enforcement, request/claim idempotency, expiry, server-authoritative exercise rewards, entitlement/version gates, and sensitive-data exclusions. Deno tests also cover exact Pushups request validation, prohibited camera data, and minimum-version comparison.

## Operational notes

- OpenAI Responses requests use strict JSON Schema structured outputs and `store: false`. OpenAI may still retain API data according to the account's data controls.
- Question generation returns `question`, `referenceAnswer`, `evaluationCriteria`, `confidence`, `sourceUsable`, and nullable `rejectionReason`. Both generation and answer evaluation must meet `confidence_threshold`; otherwise no reward is granted.
- Answer evaluation returns `pass`, `confidence`, concise supportive `feedback`, and nullable `missingConcept`. Only the reward transaction is persisted after a pass.
- Keep the OpenAI model pinned to a structured-output-capable snapshot and review it deliberately before changing.
- RevenueCat webhooks are at-least-once. Event IDs are claimed in PostgreSQL; failed or stale claims can be retried safely.
- Use Supabase logs carefully: error paths intentionally avoid learner answers and generated answer keys.
- Monitor rows left in `failed` webhook status and active sessions that outlive their expiry, and alert on cleanup or RevenueCat refresh failures.
