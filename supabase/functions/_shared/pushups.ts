import { HttpError } from "./response.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const APP_VERSION = /^[0-9]{1,9}(?:\.[0-9]{1,9}){0,2}$/;
const DETECTION_VERSION = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;
const ISO_TIMESTAMP =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;

type UnknownBody = Record<string, unknown>;

export type StartBody = {
  clientRequestId: string;
  targetReps: 5 | 10 | 20;
  appVersion: string;
  detectionVersion: string;
};

export type ClaimBody = {
  sessionId: string;
  completedReps: number;
  durationSeconds: number;
  completedAt: string;
  detectionVersion: string;
};

function bodyRecord(value: unknown): UnknownBody {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpError(400, "invalid_body", "Request body must be an object");
  }
  return value as UnknownBody;
}

function exactKeys(body: UnknownBody, allowed: string[]): void {
  const unexpected = Object.keys(body).filter((key) => !allowed.includes(key));
  if (unexpected.length > 0) {
    throw new HttpError(
      400,
      "unexpected_fields",
      `Unexpected request fields: ${unexpected.join(", ")}`,
    );
  }
}

export function validAppVersion(value: unknown): value is string {
  return typeof value === "string" && APP_VERSION.test(value);
}

export function versionAtLeast(candidate: string, minimum: string): boolean {
  if (!validAppVersion(candidate) || !validAppVersion(minimum)) return false;
  const candidateParts = candidate.split(".").map(Number);
  const minimumParts = minimum.split(".").map(Number);
  for (let index = 0; index < 3; index += 1) {
    const difference = (candidateParts[index] ?? 0) -
      (minimumParts[index] ?? 0);
    if (difference !== 0) return difference > 0;
  }
  return true;
}

function detectionVersion(value: unknown): string {
  if (typeof value !== "string" || !DETECTION_VERSION.test(value)) {
    throw new HttpError(
      400,
      "invalid_detection_version",
      "detection_version is invalid",
    );
  }
  return value;
}

export function validateStartBody(value: unknown): StartBody {
  const body = bodyRecord(value);
  exactKeys(body, [
    "client_request_id",
    "target_reps",
    "app_version",
    "detection_version",
  ]);
  if (
    typeof body.client_request_id !== "string" ||
    !UUID.test(body.client_request_id)
  ) {
    throw new HttpError(
      400,
      "invalid_request_id",
      "client_request_id must be a UUID",
    );
  }
  if (
    body.target_reps !== 5 && body.target_reps !== 10 &&
    body.target_reps !== 20
  ) {
    throw new HttpError(
      400,
      "invalid_challenge",
      "target_reps must be 5, 10, or 20",
    );
  }
  if (!validAppVersion(body.app_version)) {
    throw new HttpError(
      400,
      "invalid_app_version",
      "app_version must contain one to three numeric components",
    );
  }
  return {
    clientRequestId: body.client_request_id,
    targetReps: body.target_reps,
    appVersion: body.app_version,
    detectionVersion: detectionVersion(body.detection_version),
  };
}

export function validateClaimBody(value: unknown): ClaimBody {
  const body = bodyRecord(value);
  exactKeys(body, [
    "session_id",
    "completed_reps",
    "duration_seconds",
    "completed_at",
    "detection_version",
  ]);
  if (typeof body.session_id !== "string" || !UUID.test(body.session_id)) {
    throw new HttpError(400, "invalid_session", "session_id must be a UUID");
  }
  if (
    !Number.isInteger(body.completed_reps) ||
    (body.completed_reps as number) < 0 ||
    (body.completed_reps as number) > 1000
  ) {
    throw new HttpError(
      400,
      "invalid_completed_reps",
      "completed_reps must be an integer from 0 to 1000",
    );
  }
  if (
    typeof body.duration_seconds !== "number" ||
    !Number.isFinite(body.duration_seconds) || body.duration_seconds <= 0 ||
    body.duration_seconds > 3600
  ) {
    throw new HttpError(
      400,
      "invalid_duration",
      "duration_seconds must be greater than 0 and at most 3600",
    );
  }
  if (
    typeof body.completed_at !== "string" ||
    !ISO_TIMESTAMP.test(body.completed_at)
  ) {
    throw new HttpError(
      400,
      "invalid_completed_at",
      "completed_at must be an ISO-8601 timestamp",
    );
  }
  const completedAt = new Date(body.completed_at);
  if (!Number.isFinite(completedAt.getTime())) {
    throw new HttpError(
      400,
      "invalid_completed_at",
      "completed_at must be an ISO-8601 timestamp",
    );
  }
  return {
    sessionId: body.session_id,
    completedReps: body.completed_reps as number,
    durationSeconds: body.duration_seconds,
    completedAt: completedAt.toISOString(),
    detectionVersion: detectionVersion(body.detection_version),
  };
}
