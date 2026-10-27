import { HttpError } from "./response.ts";

export type SocialAction =
  | "overview"
  | "save_profile"
  | "delete_profile"
  | "add_friend"
  | "remove_friend"
  | "record_progress"
  | "send"
  | "create_squad"
  | "join_squad"
  | "leave_squad"
  | "mark_read";

const ACTIONS: ReadonlySet<string> = new Set([
  "overview",
  "save_profile",
  "delete_profile",
  "add_friend",
  "remove_friend",
  "record_progress",
  "send",
  "create_squad",
  "join_squad",
  "leave_squad",
  "mark_read",
]);

export type ProgressDay = {
  day: string;
  dailyGoal: number;
  activityAmount: number;
  earnedSeconds: number;
  streakDays: number;
  isFinal: boolean;
};

export type PushKind = "missed_goal" | "nudge" | "cheer" | "friend_added";

type Body = Record<string, unknown>;

function invalid(message: string): never {
  throw new HttpError(400, "invalid_request", message);
}

function object(value: unknown): Body {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    invalid("Body must be an object");
  }
  return value as Body;
}

export function validateAction(value: unknown): { action: SocialAction; body: Body } {
  const body = object(value);
  if (typeof body.action !== "string" || !ACTIONS.has(body.action)) {
    invalid("Unknown action");
  }
  return { action: body.action as SocialAction, body };
}

/** Invite codes are six characters from an alphabet without 0, O, 1 or I. */
export function normalizeInviteCode(value: unknown): string {
  if (typeof value !== "string") invalid("invite_code is required");
  const code = value.trim().toUpperCase().replace(/[\s-]/g, "");
  if (!/^[A-HJ-NP-Z2-9]{6}$/.test(code)) invalid("invite_code is invalid");
  return code;
}

export function validateDisplayName(value: unknown): string {
  if (typeof value !== "string") invalid("display_name is required");
  const name = value.trim().replace(/\s+/g, " ");
  if (name.length < 1 || [...name].length > 24) {
    invalid("display_name must be 1 to 24 characters");
  }
  return name;
}

export function validateSquadName(value: unknown): string {
  if (typeof value !== "string") invalid("name is required");
  const name = value.trim().replace(/\s+/g, " ");
  if (name.length < 1 || [...name].length > 32) {
    invalid("name must be 1 to 32 characters");
  }
  return name;
}

export function validateDay(value: unknown, field = "today"): string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    invalid(`${field} must be YYYY-MM-DD`);
  }
  const date = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== value) {
    invalid(`${field} must be a real date`);
  }
  return value;
}

export function validateUUID(value: unknown, field: string): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      value,
    )
  ) {
    invalid(`${field} must be a UUID`);
  }
  return value.toLowerCase();
}

function integer(value: unknown, field: string, max: number): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
    invalid(`${field} must be a non-negative integer`);
  }
  return Math.min(value, max);
}

/** At most a week of days; the phone sends today and yesterday. */
export function validateProgressDays(value: unknown): ProgressDay[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > 7) {
    invalid("days must hold 1 to 7 entries");
  }
  return value.map((entry) => {
    const day = object(entry);
    if (typeof day.is_final !== "boolean") invalid("is_final must be a boolean");
    return {
      day: validateDay(day.day, "day"),
      dailyGoal: integer(day.daily_goal, "daily_goal", 200_000),
      activityAmount: integer(day.activity_amount, "activity_amount", 500_000),
      earnedSeconds: integer(day.earned_seconds, "earned_seconds", 86_400),
      streakDays: integer(day.streak_days, "streak_days", 10_000),
      isFinal: day.is_final,
    };
  });
}

export function validateSendKind(value: unknown): "nudge" | "cheer" {
  if (value !== "nudge" && value !== "cheer") invalid("kind must be nudge or cheer");
  return value;
}

export function validateAPNsToken(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string" || !/^[0-9a-f]{64,200}$/.test(value)) {
    invalid("apns_token must be a lowercase hex device token");
  }
  return value;
}

export function validateAPNsEnvironment(value: unknown): "sandbox" | "production" | null {
  if (value === undefined || value === null) return null;
  if (value !== "sandbox" && value !== "production") {
    invalid("apns_environment must be sandbox or production");
  }
  return value;
}

/** Monday of the ISO week holding `day` (YYYY-MM-DD). */
export function weekStart(day: string): string {
  const date = new Date(`${day}T00:00:00Z`);
  const offset = (date.getUTCDay() + 6) % 7;
  date.setUTCDate(date.getUTCDate() - offset);
  return date.toISOString().slice(0, 10);
}

/**
 * Pushes are localised on the recipient's phone: the server does not know their language, so
 * it sends keys from the app's string catalog and the friend's name as the argument.
 */
export function pushAlert(kind: PushKind, actorName: string): Record<string, unknown> {
  return {
    "title-loc-key": `push.${kind}.title`,
    "loc-key": `push.${kind}.body`,
    "loc-args": [actorName],
  };
}
