import { adminClient, requireUser } from "../_shared/supabase.ts";
import { entitlementForUser } from "../_shared/revenuecat.ts";
import { validateClaimBody } from "../_shared/pushups.ts";
import {
  errorResponse,
  HttpError,
  json,
  method,
  readJson,
} from "../_shared/response.ts";

function rpcError(error: { code?: string; message?: string }): never {
  const message = error.message ?? "";
  if (message.includes("daily pushups reward cap")) {
    throw new HttpError(
      409,
      "daily_cap_reached",
      "The full reward would exceed the UTC daily cap",
    );
  }
  if (message.includes("active entitlement")) {
    throw new HttpError(
      403,
      "entitlement_required",
      "An active Pro entitlement is required",
    );
  }
  if (message.includes("minimum app version")) {
    throw new HttpError(
      426,
      "update_required",
      "A newer app version is required",
    );
  }
  if (message.includes("disabled")) {
    throw new HttpError(
      403,
      "pushups_disabled",
      "Pushups rewards are disabled",
    );
  }
  if (message.includes("not completed")) {
    throw new HttpError(
      422,
      "challenge_incomplete",
      "The server-selected repetition target was not completed",
    );
  }
  if (message.includes("duration")) {
    throw new HttpError(
      422,
      "invalid_duration",
      "The reported completion time is invalid",
    );
  }
  if (message.includes("completion time")) {
    throw new HttpError(
      422,
      "invalid_completion_time",
      "The reported completion time is outside the session window",
    );
  }
  if (message.includes("detection version")) {
    throw new HttpError(
      409,
      "detection_version_mismatch",
      "Detection configuration changed",
    );
  }
  if (error.code === "P0002") {
    throw new HttpError(404, "session_not_found", "Exercise session not found");
  }
  if (message.includes("not active")) {
    throw new HttpError(
      409,
      "session_inactive",
      "Exercise session is not active",
    );
  }
  throw error;
}

Deno.serve(async (request) => {
  try {
    method(request, "POST");
    const user = await requireUser(request);
    const body = validateClaimBody(await readJson<unknown>(request));
    const client = adminClient();
    const { data: config, error: configError } = await client.from(
      "exercise_configuration",
    ).select("entitlement_required").eq("id", true).single();
    if (configError) throw configError;
    if (config.entitlement_required) {
      await entitlementForUser(client, user.id);
    }
    const { data: reward, error } = await client.rpc(
      "claim_exercise_reward",
      {
        p_user_id: user.id,
        p_session_id: body.sessionId,
        p_completed_reps: body.completedReps,
        p_duration_seconds: body.durationSeconds,
        p_completed_at: body.completedAt,
        p_detection_version: body.detectionVersion,
      },
    );
    if (error) rpcError(error);
    if (!reward) {
      throw new HttpError(409, "session_expired", "Exercise session expired");
    }
    return json({
      reward: {
        id: reward.id,
        sessionId: reward.source_id,
        amountSeconds: reward.amount_seconds,
        earnedOn: reward.earned_on,
        createdAt: reward.created_at,
      },
    });
  } catch (error) {
    return errorResponse(error);
  }
});
