import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { validateGeneratedQuestion } from "../_shared/openai.ts";
import { validateStudySource } from "../_shared/study.ts";
import { verifyRevenueCatSignature } from "../_shared/webhook.ts";
import { entitlementFromWebhookEvent } from "../_shared/revenuecat.ts";
import {
  validateClaimBody,
  validateStartBody,
  versionAtLeast,
} from "../_shared/pushups.ts";

async function signature(
  body: Uint8Array,
  timestamp: number,
  secret: string,
): Promise<string> {
  const prefix = new TextEncoder().encode(`${timestamp}.`);
  const signed = new Uint8Array(prefix.length + body.length);
  signed.set(prefix);
  signed.set(body, prefix.length);
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const result = await crypto.subtle.sign("HMAC", key, signed);
  const hex = Array.from(
    new Uint8Array(result),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
  return `t=${timestamp},v1=${hex}`;
}

Deno.test("RevenueCat HMAC accepts exact raw bytes", async () => {
  const body = new TextEncoder().encode('{"event":{"id":"event-id"}}\n');
  const header = await signature(body, 1_700_000_000, "test-secret");
  assertEquals(
    await verifyRevenueCatSignature(body, header, "test-secret", 1_700_000_000),
    true,
  );
  assertEquals(
    await verifyRevenueCatSignature(
      new TextEncoder().encode('{"event":{"id":"event-id"}}'),
      header,
      "test-secret",
      1_700_000_000,
    ),
    false,
  );
});

Deno.test("RevenueCat HMAC rejects stale signatures", async () => {
  const body = new TextEncoder().encode("{}");
  const header = await signature(body, 1_700_000_000, "test-secret");
  assertEquals(
    await verifyRevenueCatSignature(body, header, "test-secret", 1_700_000_301),
    false,
  );
});

Deno.test("expiration webhook revokes entitlement", () => {
  const state = entitlementFromWebhookEvent({
    type: "EXPIRATION",
    expiration_at_ms: 1_700_000_000_000,
    environment: "SANDBOX",
  });
  assertEquals(state.is_active, false);
  assertEquals(state.environment, "SANDBOX");
});

Deno.test("question validation accepts supported confident source output", () => {
  const generated = {
    question: "What process is described?",
    referenceAnswer: "Photosynthesis",
    evaluationCriteria: "Names photosynthesis",
    confidence: 0.9,
    sourceUsable: true,
    rejectionReason: null,
  };
  assertEquals(validateGeneratedQuestion(generated, 0.7), generated);
});

Deno.test("question validation rejects unusable or low-confidence source", () => {
  assertThrows(
    () =>
      validateGeneratedQuestion({
        question: "",
        referenceAnswer: "",
        evaluationCriteria: "",
        confidence: 0.9,
        sourceUsable: false,
        rejectionReason: "OCR is unreadable",
      }, 0.7),
    Error,
    "OCR is unreadable",
  );
  assertThrows(
    () =>
      validateGeneratedQuestion({
        question: "Question",
        referenceAnswer: "Answer",
        evaluationCriteria: "Criteria",
        confidence: 0.69,
        sourceUsable: true,
        rejectionReason: null,
      }, 0.7),
    Error,
    "not reliable enough",
  );
});

Deno.test("study source validation trims and enforces source and locale", () => {
  assertEquals(validateStudySource("  readable OCR text  ", "en-US", 10, 100), {
    sourceText: "readable OCR text",
    locale: "en-US",
  });
  assertThrows(
    () => validateStudySource("short", "en", 10, 100),
    Error,
    "10 to 100",
  );
  assertThrows(
    () => validateStudySource("long enough OCR", "not_a_locale", 10, 100),
    Error,
    "BCP 47",
  );
});

Deno.test("pushups version comparison handles numeric components", () => {
  assertEquals(versionAtLeast("2.1", "2.1.0"), true);
  assertEquals(versionAtLeast("2.1.1", "2.1.0"), true);
  assertEquals(versionAtLeast("2.0.9", "2.1.0"), false);
  assertEquals(versionAtLeast("2.1-beta", "2.1.0"), false);
  assertEquals(versionAtLeast("1234567890.1", "2.1.0"), false);
});

Deno.test("pushups start accepts only supported challenges and metadata", () => {
  assertEquals(
    validateStartBody({
      client_request_id: "10000000-0000-4000-8000-000000000001",
      target_reps: 10,
      app_version: "2.1.0",
      detection_version: "pose-v1",
    }),
    {
      clientRequestId: "10000000-0000-4000-8000-000000000001",
      targetReps: 10,
      appVersion: "2.1.0",
      detectionVersion: "pose-v1",
    },
  );
  assertThrows(
    () =>
      validateStartBody({
        client_request_id: "10000000-0000-4000-8000-000000000001",
        target_reps: 15,
        app_version: "2.1.0",
        detection_version: "pose-v1",
      }),
    Error,
    "5, 10, or 20",
  );
});

Deno.test("pushups claim accepts completion summary without camera data", () => {
  assertEquals(
    validateClaimBody({
      session_id: "20000000-0000-4000-8000-000000000001",
      completed_reps: 20,
      duration_seconds: 18.25,
      completed_at: "2026-09-14T12:00:00Z",
      detection_version: "pose-v1",
    }),
    {
      sessionId: "20000000-0000-4000-8000-000000000001",
      completedReps: 20,
      durationSeconds: 18.25,
      completedAt: "2026-09-14T12:00:00.000Z",
      detectionVersion: "pose-v1",
    },
  );
  assertThrows(
    () =>
      validateClaimBody({
        session_id: "20000000-0000-4000-8000-000000000001",
        completed_reps: 20,
        duration_seconds: 18.25,
        completed_at: "2026-09-14T12:00:00Z",
        detection_version: "pose-v1",
        landmarks: [[0.1, 0.2]],
      }),
    Error,
    "Unexpected request fields: landmarks",
  );
  assertThrows(
    () =>
      validateClaimBody({
        session_id: "20000000-0000-4000-8000-000000000001",
        completed_reps: 20,
        duration_seconds: 18.25,
        completed_at: "2026-09-14T12:00:00Z",
        detection_version: "pose-v1",
        frames: ["base64"],
      }),
    Error,
    "Unexpected request fields: frames",
  );
  assertThrows(
    () =>
      validateClaimBody({
        session_id: "20000000-0000-4000-8000-000000000001",
        completed_reps: 20,
        duration_seconds: 18.25,
        completed_at: "2026-09-14",
        detection_version: "pose-v1",
      }),
    Error,
    "ISO-8601 timestamp",
  );
});
