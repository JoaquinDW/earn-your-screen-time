import {
  adminClient,
  cleanupExpired,
  requireUser,
} from "../_shared/supabase.ts";
import { entitlementForUser } from "../_shared/revenuecat.ts";
import { generateQuestion } from "../_shared/openai.ts";
import { validateStudySource } from "../_shared/study.ts";
import {
  errorResponse,
  HttpError,
  json,
  method,
  readJson,
} from "../_shared/response.ts";

type Body = {
  action?: "start" | "regenerate" | "abandon";
  session_id?: string;
  client_request_id?: string;
  source_text?: string;
  locale?: string;
};
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

async function prepareGeneration(
  client: ReturnType<typeof adminClient>,
  userId: string,
  clientRequestId: string | null,
  sessionId: string | null,
  clearOtherActive: boolean,
): Promise<boolean> {
  const { data, error } = await client.rpc("prepare_study_generation", {
    p_user_id: userId,
    p_client_request_id: clientRequestId,
    p_session_id: sessionId,
    p_clear_other_active: clearOtherActive,
  });
  if (!error) return data;
  if (error.message?.includes("daily study reward cap")) {
    throw new HttpError(
      409,
      "daily_cap_reached",
      "There is not enough daily capacity for a full study reward",
    );
  }
  if (error.message?.includes("active entitlement required")) {
    throw new HttpError(
      403,
      "entitlement_required",
      "An active subscription is required",
    );
  }
  if (error.message?.includes("study rewards are disabled")) {
    throw new HttpError(
      403,
      "study_disabled",
      "Study rewards are currently disabled",
    );
  }
  if (error.code === "P0002") {
    throw new HttpError(409, "session_inactive", "Study session is not active");
  }
  throw error;
}

async function requireStudyAccess(
  client: ReturnType<typeof adminClient>,
  config: Record<string, unknown>,
  userId: string,
): Promise<void> {
  if (!config.enabled) {
    throw new HttpError(
      403,
      "study_disabled",
      "Study rewards are currently disabled",
    );
  }
  if (
    config.entitlement_required && !await entitlementForUser(client, userId)
  ) {
    throw new HttpError(
      403,
      "entitlement_required",
      "An active subscription is required",
    );
  }
}

Deno.serve(async (request) => {
  try {
    method(request, "POST");
    const user = await requireUser(request);
    const body = await readJson<Body>(request);
    const client = adminClient();
    await cleanupExpired(client);
    const { data: config, error: configError } = await client.from(
      "study_configuration",
    ).select("*").eq("id", true).single();
    if (configError) throw configError;

    if (body.action === "start") {
      if (!body.client_request_id || !UUID.test(body.client_request_id)) {
        throw new HttpError(
          400,
          "invalid_request_id",
          "client_request_id must be a UUID",
        );
      }
      const { sourceText, locale } = validateStudySource(
        body.source_text,
        body.locale,
        config.source_text_min_length,
        config.source_text_max_length,
      );
      const { data: existing, error: existingError } = await client.from(
        "study_sessions",
      )
        .select(
          "id,status,question,expires_at,regeneration_count,answer_attempt_count",
        )
        .eq("user_id", user.id).eq("client_request_id", body.client_request_id)
        .maybeSingle();
      if (existingError) throw existingError;
      if (existing) return json({ session: existing, idempotent: true });
      await requireStudyAccess(client, config, user.id);
      const shouldGenerate = await prepareGeneration(
        client,
        user.id,
        body.client_request_id,
        null,
        true,
      );
      if (!shouldGenerate) {
        const { data: racedExisting, error: racedExistingError } = await client
          .from("study_sessions")
          .select(
            "id,status,question,expires_at,regeneration_count,answer_attempt_count",
          )
          .eq("user_id", user.id)
          .eq("client_request_id", body.client_request_id)
          .single();
        if (racedExistingError) throw racedExistingError;
        return json({ session: racedExisting, idempotent: true });
      }
      const generated = await generateQuestion(
        config,
        sourceText,
        locale,
        undefined,
        request.signal,
      );
      const expiresAt = new Date(Date.now() + config.session_ttl_seconds * 1000)
        .toISOString();
      const { data, error } = await client.from("study_sessions").insert({
        user_id: user.id,
        client_request_id: body.client_request_id,
        source_text: sourceText,
        locale,
        question: generated.question,
        reference_answer: generated.referenceAnswer,
        evaluation_criteria: generated.evaluationCriteria,
        generation_confidence: generated.confidence,
        reward_seconds: config.reward_seconds,
        expires_at: expiresAt,
      }).select(
        "id,status,question,expires_at,regeneration_count,answer_attempt_count",
      ).single();
      if (error) {
        if (error.code === "23505") {
          throw new HttpError(
            409,
            "session_conflict",
            "A study session is already active",
          );
        }
        throw error;
      }
      return json({ session: data }, 201);
    }

    if (!body.session_id || !UUID.test(body.session_id)) {
      throw new HttpError(400, "invalid_session", "session_id must be a UUID");
    }
    const { data: session, error: sessionError } = await client.from(
      "study_sessions",
    ).select("*")
      .eq("id", body.session_id).eq("user_id", user.id).maybeSingle();
    if (sessionError) throw sessionError;
    if (!session) {
      throw new HttpError(404, "session_not_found", "Study session not found");
    }
    if (session.status !== "active") {
      throw new HttpError(
        409,
        "session_inactive",
        "Study session is not active",
      );
    }

    if (body.action === "abandon") {
      const { data, error } = await client.from("study_sessions").update({
        status: "abandoned",
        source_text: null,
        reference_answer: null,
        evaluation_criteria: null,
        completed_at: new Date().toISOString(),
      }).eq("id", session.id).eq("user_id", user.id).eq("status", "active")
        .select("id,status").maybeSingle();
      if (error) throw error;
      if (!data) {
        throw new HttpError(
          409,
          "session_conflict",
          "The session changed; retry the request",
        );
      }
      return json({ session: data });
    }

    if (body.action === "regenerate") {
      if (session.regeneration_count >= config.max_regenerations) {
        throw new HttpError(
          409,
          "regeneration_limit",
          "This session cannot be regenerated again",
        );
      }
      await requireStudyAccess(client, config, user.id);
      await prepareGeneration(client, user.id, null, session.id, false);
      const generated = await generateQuestion(
        config,
        session.source_text,
        session.locale,
        session.question,
        request.signal,
      );
      const { data, error } = await client.from("study_sessions").update({
        question: generated.question,
        reference_answer: generated.referenceAnswer,
        evaluation_criteria: generated.evaluationCriteria,
        generation_confidence: generated.confidence,
        regeneration_count: session.regeneration_count + 1,
      }).eq("id", session.id).eq("user_id", user.id).eq("status", "active")
        .eq("regeneration_count", session.regeneration_count)
        .select(
          "id,status,question,expires_at,regeneration_count,answer_attempt_count",
        ).maybeSingle();
      if (error) throw error;
      if (!data) {
        throw new HttpError(
          409,
          "session_conflict",
          "The session changed; retry the request",
        );
      }
      return json({ session: data });
    }
    throw new HttpError(
      400,
      "invalid_action",
      "action must be start, regenerate, or abandon",
    );
  } catch (error) {
    return errorResponse(error);
  }
});
