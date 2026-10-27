import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  normalizeInviteCode,
  pushAlert,
  validateAction,
  validateDay,
  validateDisplayName,
  validateProgressDays,
  validateSendKind,
  weekStart,
} from "../_shared/social.ts";
import { pemToDer } from "../_shared/apns.ts";

Deno.test("invite codes are normalised and skip ambiguous characters", () => {
  assertEquals(normalizeInviteCode(" k7q-2mx "), "K7Q2MX");
  assertThrows(() => normalizeInviteCode("K7Q2M0"));
  assertThrows(() => normalizeInviteCode("K7Q2M"));
  assertThrows(() => normalizeInviteCode(42));
});

Deno.test("display names are trimmed and capped at 24 characters", () => {
  assertEquals(validateDisplayName("  Ana   María "), "Ana María");
  assertThrows(() => validateDisplayName("   "));
  assertThrows(() => validateDisplayName("x".repeat(25)));
});

Deno.test("days must be real calendar days", () => {
  assertEquals(validateDay("2026-10-27"), "2026-10-27");
  assertThrows(() => validateDay("2026-02-30"));
  assertThrows(() => validateDay("27/10/2026"));
});

Deno.test("progress days are validated and clamped", () => {
  const [day] = validateProgressDays([{
    day: "2026-10-26",
    daily_goal: 8000,
    activity_amount: 900000,
    earned_seconds: 600,
    streak_days: 3,
    is_final: true,
  }]);
  assertEquals(day.activityAmount, 500000);
  assertEquals(day.isFinal, true);
  assertThrows(() => validateProgressDays([]));
  assertThrows(() =>
    validateProgressDays([{ day: "2026-10-26", daily_goal: -1, activity_amount: 0, earned_seconds: 0, streak_days: 0, is_final: false }])
  );
});

Deno.test("only known actions and send kinds are accepted", () => {
  assertEquals(validateAction({ action: "overview" }).action, "overview");
  assertThrows(() => validateAction({ action: "drop_tables" }));
  assertEquals(validateSendKind("cheer"), "cheer");
  assertThrows(() => validateSendKind("spam"));
});

Deno.test("league weeks start on Monday", () => {
  assertEquals(weekStart("2026-10-27"), "2026-10-26");
  assertEquals(weekStart("2026-10-26"), "2026-10-26");
  assertEquals(weekStart("2026-11-01"), "2026-10-26");
});

Deno.test("pushes are localised on the phone", () => {
  assertEquals(pushAlert("nudge", "Ana"), {
    "title-loc-key": "push.nudge.title",
    "loc-key": "push.nudge.body",
    "loc-args": ["Ana"],
  });
});

Deno.test("a .p8 key pasted with escaped newlines still decodes", () => {
  const pem = "-----BEGIN PRIVATE KEY-----\\nAQID\\n-----END PRIVATE KEY-----";
  assertEquals([...pemToDer(pem)], [1, 2, 3]);
});
