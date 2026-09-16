import {
  adminClient,
  cleanupExpired,
  requireUser,
} from "../_shared/supabase.ts";
import { gradeAnswer } from "../_shared/openai.ts";
import { entitlementForUser } from "../_shared/revenuecat.ts";
import {
  errorResponse,
  HttpError,
  json,
  method,
  readJson,
} from "../_shared/response.ts";

type Body = { session_id?: string; answer?: string };
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

Deno.serve(async (request) => {
  try {
    method(request, "POST");
    const user = await requireUser(request);
    const body = await readJson<Body>(request);
    if (!body.session_id || !UUID.test(body.session_id)) {
      throw new HttpError(400, "invalid_session", "session_id must be a UUID");
    }
    const answer = body.answer?.trim();
    if (!answer || answer.length > 2000) {
      throw new HttpError(
        400,
        "invalid_answer",
        "answer must contain 1 to 2000 characters",
      );
    }
    const client = adminClient();
    await cleanupExpired(client);
    const { data: config, error: configError } = await client.from(
      "study_configuration",
    )
      .select(
        "enabled,entitlement_required,grading_instructions,confidence_threshold",
      ).eq(
        "id",
        true,
      ).single();
    if (configError) throw configError;
    const { data: session, error } = await client.from("study_sessions")
      .select(
        "id,status,question,reference_answer,evaluation_criteria,regeneration_count,answer_attempt_count",
      )
      .eq("id", body.session_id).eq("user_id", user.id).maybeSingle();
    if (error) throw error;
    if (!session) {
      throw new HttpError(404, "session_not_found", "Study session not found");
    }
    if (session.status === "passed") {
      const { data: reward, error: rewardError } = await client.from(
        "study_reward_transactions",
      )
        .select("id,session_id,amount_seconds,earned_on,created_at").eq(
          "session_id",
          session.id,
        ).single();
      if (rewardError) throw rewardError;
      return json({ pass: true, reward, idempotent: true });
    }
    if (!config.enabled) {
      throw new HttpError(
        403,
        "study_disabled",
        "Study rewards are currently disabled",
      );
    }
    if (
      config.entitlement_required && !await entitlementForUser(client, user.id)
    ) {
      throw new HttpError(
        403,
        "entitlement_required",
        "An active subscription is required",
      );
    }
    if (
      session.status !== "active" || !session.reference_answer ||
      !session.evaluation_criteria
    ) {
      throw new HttpError(
        409,
        "session_inactive",
        "Study session is not active",
      );
    }
    if (session.answer_attempt_count >= 100) {
      throw new HttpError(
        409,
        "attempt_limit",
        "This session has reached its answer limit",
      );
    }
    const grade = await gradeAnswer(
      session.question,
      session.reference_answer,
      session.evaluation_criteria,
      answer,
      config.grading_instructions,
      request.signal,
    );
    const accepted = grade.pass &&
      grade.confidence >= Number(config.confidence_threshold);
    if (!accepted) {
      const { error: updateError } = await client.from("study_sessions")
        .update({ answer_attempt_count: session.answer_attempt_count + 1 })
        .eq("id", session.id).eq("user_id", user.id).eq("status", "active")
        .eq("answer_attempt_count", session.answer_attempt_count);
      if (updateError) throw updateError;
      return json({
        pass: false,
        confidence: grade.confidence,
        feedback: grade.feedback,
        missingConcept: grade.missingConcept,
      });
    }
    const { data: reward, error: rewardError } = await client.rpc(
      "grant_study_reward",
      {
        p_user_id: user.id,
        p_session_id: session.id,
        p_regeneration_count: session.regeneration_count,
      },
    );
    if (rewardError) {
      if (rewardError.message?.includes("daily study reward cap")) {
        throw new HttpError(
          409,
          "daily_cap_reached",
          "The daily study reward cap has been reached",
        );
      }
      if (rewardError.code === "40001") {
        throw new HttpError(
          409,
          "question_changed",
          "The question changed; answer the current question",
        );
      }
      throw rewardError;
    }
    if (!reward) {
      throw new HttpError(409, "session_expired", "Study session expired");
    }
    return json({
      pass: true,
      confidence: grade.confidence,
      feedback: grade.feedback,
      missingConcept: grade.missingConcept,
      reward: {
        id: reward.id,
        session_id: reward.session_id,
        amount_seconds: reward.amount_seconds,
        earned_on: reward.earned_on,
        created_at: reward.created_at,
      },
    });
  } catch (error) {
    return errorResponse(error);
  }
});
