import { adminClient, requireUser } from "../_shared/supabase.ts";
import { entitlementForUser } from "../_shared/revenuecat.ts";
import { errorResponse, HttpError, json, method } from "../_shared/response.ts";
import { validAppVersion, versionAtLeast } from "../_shared/pushups.ts";

Deno.serve(async (request) => {
  try {
    method(request, "GET");
    const user = await requireUser(request);
    const appVersion = new URL(request.url).searchParams.get("app_version");
    if (appVersion !== null && !validAppVersion(appVersion)) {
      throw new HttpError(
        400,
        "invalid_app_version",
        "app_version must contain one to three numeric components",
      );
    }
    const client = adminClient();
    const { data: configuration, error } = await client.from(
      "exercise_configuration",
    ).select(
      "enabled,entitlement_required,free_rewards_per_user,daily_cap_seconds,session_ttl_seconds,minimum_app_version,detection_version,minimum_pose_confidence,down_elbow_angle_degrees,up_elbow_angle_degrees,minimum_body_angle_degrees,minimum_rep_duration_seconds",
    ).eq("id", true).single();
    if (error) throw error;
    const { data: challenges, error: challengesError } = await client.from(
      "exercise_challenges",
    ).select("target_reps,reward_seconds").eq("enabled", true).order(
      "display_order",
    );
    if (challengesError) throw challengesError;

    const utcDay = new Date().toISOString().slice(0, 10);
    const { data: rewards, error: rewardsError } = await client.from(
      "reward_transactions",
    ).select("amount_seconds").eq("user_id", user.id).eq("earned_on", utcDay)
      .eq("source_type", "pushups");
    if (rewardsError) throw rewardsError;
    const earnedSeconds = rewards.reduce(
      (total, reward) => total + reward.amount_seconds,
      0,
    );
    const remainingSeconds = Math.max(
      0,
      configuration.daily_cap_seconds - earnedSeconds,
    );
    const tomorrow = new Date();
    tomorrow.setUTCDate(tomorrow.getUTCDate() + 1);
    tomorrow.setUTCHours(0, 0, 0, 0);
    const subscribed = configuration.entitlement_required
      ? await entitlementForUser(client, user.id)
      : true;
    // Mirrors private.exercise_reward_allowed: someone who has not paid gets
    // `free_rewards_per_user` push-up rewards over the account's lifetime.
    const { count: lifetimeRewards, error: lifetimeError } = await client.from(
      "reward_transactions",
    ).select("id", { count: "exact", head: true }).eq("user_id", user.id).eq(
      "source_type",
      "pushups",
    );
    if (lifetimeError) throw lifetimeError;
    const freeRewardsRemaining = subscribed ? 0 : Math.max(
      0,
      configuration.free_rewards_per_user - (lifetimeRewards ?? 0),
    );
    const entitled = subscribed || freeRewardsRemaining > 0;

    return json({
      configuration: {
        enabled: configuration.enabled,
        minimumAppVersion: configuration.minimum_app_version,
        detectionVersion: configuration.detection_version,
        sessionTtlSeconds: configuration.session_ttl_seconds,
        dailyCapSeconds: configuration.daily_cap_seconds,
        poseThresholds: {
          minimumConfidence: Number(configuration.minimum_pose_confidence),
          downElbowAngleDegrees: Number(
            configuration.down_elbow_angle_degrees,
          ),
          upElbowAngleDegrees: Number(configuration.up_elbow_angle_degrees),
          minimumBodyAngleDegrees: Number(
            configuration.minimum_body_angle_degrees,
          ),
          minimumRepDurationSeconds: Number(
            configuration.minimum_rep_duration_seconds,
          ),
        },
        challenges: challenges.map((challenge) => ({
          targetReps: challenge.target_reps,
          rewardSeconds: challenge.reward_seconds,
        })),
      },
      entitled,
      freeRewardsRemaining,
      updateRequired: appVersion === null
        ? null
        : !versionAtLeast(appVersion, configuration.minimum_app_version),
      availability: {
        earnedSeconds,
        rewardSecondsRemaining: remainingSeconds,
        resetsAt: tomorrow.toISOString(),
      },
    });
  } catch (error) {
    return errorResponse(error);
  }
});
