import { adminClient, requireUser } from "../_shared/supabase.ts";
import { entitlementForUser } from "../_shared/revenuecat.ts";
import { errorResponse, json, method } from "../_shared/response.ts";

Deno.serve(async (request) => {
  try {
    method(request, "GET");
    const user = await requireUser(request);
    const client = adminClient();
    const { data, error } = await client.from("study_configuration")
      .select(
        "enabled,entitlement_required,questions_per_session,passing_score,reward_seconds,daily_cap_seconds,session_ttl_seconds,max_regenerations,source_text_min_length,source_text_max_length,confidence_threshold,difficulty",
      )
      .eq("id", true).single();
    if (error) throw error;
    const utcDay = new Date().toISOString().slice(0, 10);
    const { data: rewards, error: rewardsError } = await client.from(
      "study_reward_transactions",
    ).select("amount_seconds").eq("user_id", user.id).eq("earned_on", utcDay);
    if (rewardsError) throw rewardsError;
    const earnedSeconds = rewards.reduce(
      (total, reward) => total + reward.amount_seconds,
      0,
    );
    const remainingSeconds = Math.max(
      0,
      data.daily_cap_seconds - earnedSeconds,
    );
    const completionsToday = rewards.length;
    const canEarnFullReward = remainingSeconds >= data.reward_seconds;
    const tomorrow = new Date();
    tomorrow.setUTCDate(tomorrow.getUTCDate() + 1);
    tomorrow.setUTCHours(0, 0, 0, 0);
    const entitled = data.entitlement_required
      ? await entitlementForUser(client, user.id)
      : true;
    return json({
      configuration: data,
      entitled,
      availability: {
        completionsToday,
        earnedSeconds,
        rewardSecondsRemaining: remainingSeconds,
        canEarnFullReward,
        nextAvailableAt: canEarnFullReward ? null : tomorrow.toISOString(),
        resetsAt: tomorrow.toISOString(),
      },
    });
  } catch (error) {
    return errorResponse(error);
  }
});
