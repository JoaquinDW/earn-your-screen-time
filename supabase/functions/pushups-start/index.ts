import { adminClient, requireUser } from "../_shared/supabase.ts";
import { entitlementForUser } from "../_shared/revenuecat.ts";
import { validateStartBody } from "../_shared/pushups.ts";
import {
  errorResponse,
  HttpError,
  json,
  method,
  readJson,
} from "../_shared/response.ts";

function rpcError(error: { code?: string; message?: string }): never {
  const message = error.message ?? "";
  if (message.includes("disabled")) {
    throw new HttpError(
      403,
      "pushups_disabled",
      "Pushups rewards are disabled",
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
  if (message.includes("detection version")) {
    throw new HttpError(
      409,
      "detection_version_unsupported",
      "Detection configuration changed",
    );
  }
  if (message.includes("daily pushups reward cap")) {
    throw new HttpError(
      409,
      "daily_cap_reached",
      "The UTC daily Pushups reward cap has been reached",
    );
  }
  if (message.includes("already active")) {
    throw new HttpError(
      409,
      "session_active",
      "An exercise session is already active",
    );
  }
  if (error.code === "22023") {
    throw new HttpError(
      400,
      "invalid_challenge",
      "The selected challenge is unavailable",
    );
  }
  throw error;
}

Deno.serve(async (request) => {
  try {
    method(request, "POST");
    const user = await requireUser(request);
    const body = validateStartBody(await readJson<unknown>(request));
    const client = adminClient();
    const { data: config, error: configError } = await client.from(
      "exercise_configuration",
    ).select("entitlement_required").eq("id", true).single();
    if (configError) throw configError;
    if (config.entitlement_required) {
      await entitlementForUser(client, user.id);
    }
    const { data: session, error } = await client.rpc(
      "start_exercise_session",
      {
        p_user_id: user.id,
        p_client_request_id: body.clientRequestId,
        p_target_reps: body.targetReps,
        p_app_version: body.appVersion,
        p_detection_version: body.detectionVersion,
      },
    );
    if (error) rpcError(error);
    return json({
      session: {
        id: session.id,
        status: session.status,
        targetReps: session.target_reps,
        rewardSeconds: session.reward_seconds,
        expiresAt: session.expires_at,
        detectionVersion: session.detection_version,
      },
    }, 201);
  } catch (error) {
    return errorResponse(error);
  }
});
