import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { adminClient, requireUser } from "../_shared/supabase.ts";
import { apnsConfiguration, sendPush } from "../_shared/apns.ts";
import {
  normalizeInviteCode,
  pushAlert,
  type PushKind,
  validateAction,
  validateAPNsEnvironment,
  validateAPNsToken,
  validateDay,
  validateDisplayName,
  validateProgressDays,
  validateSendKind,
  validateSquadName,
  validateUUID,
  weekStart,
} from "../_shared/social.ts";
import {
  errorResponse,
  HttpError,
  json,
  method,
  readJson,
} from "../_shared/response.ts";

type Profile = {
  user_id: string;
  display_name: string;
  invite_code: string;
  share_misses: boolean;
  apns_token: string | null;
  apns_environment: "sandbox" | "production" | null;
};

type ProgressRow = {
  user_id: string;
  day: string;
  daily_goal: number;
  activity_amount: number;
  earned_seconds: number;
  streak_days: number;
  is_final: boolean;
};

function rpcError(error: { code?: string; message?: string }): never {
  const message = error.message ?? "";
  const known: Array<[string, number, string]> = [
    ["social profile required", 409, "profile_required"],
    ["invite code not found", 404, "code_not_found"],
    ["cannot add yourself", 400, "own_code"],
    ["friend limit reached", 409, "friend_limit"],
    ["squad limit reached", 409, "squad_limit"],
    ["squad is full", 409, "squad_full"],
    ["not friends", 403, "not_friends"],
    ["not a squad member", 403, "not_member"],
    ["day out of range", 400, "invalid_day"],
    ["display name is required", 400, "invalid_request"],
  ];
  for (const [fragment, status, code] of known) {
    if (message.includes(fragment)) throw new HttpError(status, code, fragment);
  }
  throw error;
}

function publicProfile(profile: Profile) {
  return {
    userId: profile.user_id,
    displayName: profile.display_name,
    inviteCode: profile.invite_code,
    shareMisses: profile.share_misses,
    pushEnabled: profile.apns_token !== null,
  };
}

function progress(row: ProgressRow | undefined) {
  if (!row) return null;
  return {
    day: row.day,
    dailyGoal: row.daily_goal,
    activityAmount: row.activity_amount,
    earnedSeconds: row.earned_seconds,
    streakDays: row.streak_days,
    isFinal: row.is_final,
  };
}

async function profileFor(
  client: SupabaseClient,
  userId: string,
): Promise<Profile | null> {
  const { data, error } = await client.from("social_profiles").select("*")
    .eq("user_id", userId).maybeSingle();
  if (error) throw error;
  return data as Profile | null;
}

async function requireProfile(
  client: SupabaseClient,
  userId: string,
): Promise<Profile> {
  const profile = await profileFor(client, userId);
  if (!profile) {
    throw new HttpError(409, "profile_required", "Create a profile first");
  }
  return profile;
}

/** Best effort: a push that fails never fails the request, the event is in the inbox either way. */
async function notify(
  client: SupabaseClient,
  recipientIds: string[],
  kind: PushKind,
  actor: Profile,
): Promise<void> {
  const configuration = apnsConfiguration();
  if (!configuration || recipientIds.length === 0) return;
  const { data, error } = await client.from("social_profiles")
    .select("user_id, apns_token, apns_environment")
    .in("user_id", recipientIds)
    .not("apns_token", "is", null);
  if (error) {
    console.error("Could not load push tokens");
    return;
  }
  await Promise.all(
    (data as Pick<Profile, "user_id" | "apns_token" | "apns_environment">[])
      .map(async (recipient) => {
        const result = await sendPush(
          configuration,
          {
            token: recipient.apns_token!,
            environment: recipient.apns_environment ?? "production",
          },
          pushAlert(kind, actor.display_name),
          // The key the app's notification delegate reads to report and route the open.
          { "earnit.notification.kind": kind },
        );
        if (result === "invalid_token") {
          await client.from("social_profiles").update({
            apns_token: null,
            updated_at: new Date().toISOString(),
          }).eq("user_id", recipient.user_id).eq(
            "apns_token",
            recipient.apns_token,
          );
        }
      }),
  );
}

async function friendIds(
  client: SupabaseClient,
  userId: string,
): Promise<string[]> {
  const { data, error } = await client.from("friendships")
    .select("user_low, user_high")
    .or(`user_low.eq.${userId},user_high.eq.${userId}`);
  if (error) throw error;
  return (data as { user_low: string; user_high: string }[]).map((row) =>
    row.user_low === userId ? row.user_high : row.user_low
  );
}

async function overview(
  client: SupabaseClient,
  userId: string,
  today: string,
) {
  const profile = await profileFor(client, userId);
  if (!profile) {
    return { profile: null, friends: [], squads: [], events: [] };
  }

  const ids = await friendIds(client, userId);
  const yesterdayDate = new Date(`${today}T00:00:00Z`);
  yesterdayDate.setUTCDate(yesterdayDate.getUTCDate() - 1);
  const yesterday = yesterdayDate.toISOString().slice(0, 10);

  let friends: unknown[] = [];
  if (ids.length > 0) {
    const [profiles, days, sent] = await Promise.all([
      client.from("social_profiles").select("user_id, display_name").in(
        "user_id",
        ids,
      ),
      client.from("daily_progress").select("*").in("user_id", ids).in("day", [
        today,
        yesterday,
      ]),
      client.from("social_events").select("recipient_id, kind").eq(
        "actor_id",
        userId,
      ).eq("day", today).in("kind", ["nudge", "cheer"]),
    ]);
    if (profiles.error) throw profiles.error;
    if (days.error) throw days.error;
    if (sent.error) throw sent.error;
    const rows = days.data as ProgressRow[];
    const sentRows = sent.data as { recipient_id: string; kind: string }[];
    friends = (profiles.data as { user_id: string; display_name: string }[])
      .map((friend) => ({
        userId: friend.user_id,
        displayName: friend.display_name,
        today: progress(
          rows.find((row) => row.user_id === friend.user_id && row.day === today),
        ),
        yesterday: progress(
          rows.find((row) =>
            row.user_id === friend.user_id && row.day === yesterday
          ),
        ),
        nudgedToday: sentRows.some((row) =>
          row.recipient_id === friend.user_id && row.kind === "nudge"
        ),
        cheeredToday: sentRows.some((row) =>
          row.recipient_id === friend.user_id && row.kind === "cheer"
        ),
      }))
      .sort((a, b) => a.displayName.localeCompare(b.displayName));
  }

  const { data: memberships, error: membershipError } = await client.from(
    "squad_members",
  ).select("squad_id, squads(id, name, invite_code)").eq("user_id", userId);
  if (membershipError) throw membershipError;
  const week = weekStart(today);
  const squads = await Promise.all(
    (memberships as unknown as {
      squads: { id: string; name: string; invite_code: string };
    }[]).map(async ({ squads: squad }) => {
      const { data, error } = await client.rpc("social_squad_standings", {
        p_user_id: userId,
        p_squad_id: squad.id,
        p_week_start: week,
      });
      if (error) rpcError(error);
      return {
        id: squad.id,
        name: squad.name,
        inviteCode: squad.invite_code,
        weekStart: week,
        standings: (data as {
          user_id: string;
          display_name: string;
          goal_days: number;
          earned_seconds: number;
          streak_days: number;
        }[]).map((row) => ({
          userId: row.user_id,
          displayName: row.display_name,
          goalDays: row.goal_days,
          earnedSeconds: row.earned_seconds,
          streakDays: row.streak_days,
        })),
      };
    }),
  );

  const since = new Date(Date.now() - 7 * 24 * 3600 * 1000).toISOString();
  const { data: events, error: eventsError } = await client.from(
    "social_events",
  ).select("id, kind, day, created_at, read_at, actor:social_profiles!social_events_actor_id_fkey(display_name)")
    .eq("recipient_id", userId).gte("created_at", since)
    .order("created_at", { ascending: false }).limit(30);
  if (eventsError) throw eventsError;

  return {
    profile: publicProfile(profile),
    friends,
    squads,
    events: (events as unknown as {
      id: string;
      kind: string;
      day: string;
      created_at: string;
      read_at: string | null;
      actor: { display_name: string } | null;
    }[]).map((event) => ({
      id: event.id,
      kind: event.kind,
      day: event.day,
      createdAt: event.created_at,
      isRead: event.read_at !== null,
      actorName: event.actor?.display_name ?? "",
    })),
  };
}

Deno.serve(async (request) => {
  try {
    method(request, "POST");
    const user = await requireUser(request);
    const { action, body } = validateAction(await readJson<unknown>(request));
    const client = adminClient();

    switch (action) {
      case "overview":
        return json(await overview(client, user.id, validateDay(body.today)));

      case "save_profile": {
        const existing = await profileFor(client, user.id);
        const displayName = body.display_name === undefined && existing
          ? null
          : validateDisplayName(body.display_name);
        if (
          body.share_misses !== undefined &&
          typeof body.share_misses !== "boolean"
        ) {
          throw new HttpError(400, "invalid_request", "share_misses must be a boolean");
        }
        const { data, error } = await client.rpc("social_upsert_profile", {
          p_user_id: user.id,
          p_display_name: displayName,
          p_share_misses: body.share_misses ?? null,
          p_apns_token: validateAPNsToken(body.apns_token),
          p_apns_environment: validateAPNsEnvironment(body.apns_environment),
        });
        if (error) rpcError(error);
        return json({ profile: publicProfile(data as Profile) });
      }

      case "delete_profile": {
        const { error } = await client.from("social_profiles").delete().eq(
          "user_id",
          user.id,
        );
        if (error) throw error;
        return json({ deleted: true });
      }

      case "add_friend": {
        const actor = await requireProfile(client, user.id);
        const { data, error } = await client.rpc("social_add_friend", {
          p_user_id: user.id,
          p_invite_code: normalizeInviteCode(body.invite_code),
          p_today: validateDay(body.today),
        });
        if (error) rpcError(error);
        const friend = data as Profile;
        await notify(client, [friend.user_id], "friend_added", actor);
        return json({
          friend: { userId: friend.user_id, displayName: friend.display_name },
        }, 201);
      }

      case "remove_friend": {
        const friendId = validateUUID(body.friend_id, "friend_id");
        const [low, high] = [user.id, friendId].sort();
        const { error } = await client.from("friendships").delete()
          .eq("user_low", low).eq("user_high", high);
        if (error) throw error;
        return json({ removed: true });
      }

      case "record_progress": {
        const actor = await requireProfile(client, user.id);
        const days = validateProgressDays(body.days);
        const recipients = new Set<string>();
        for (const day of days) {
          const { data, error } = await client.rpc("social_record_progress", {
            p_user_id: user.id,
            p_day: day.day,
            p_daily_goal: day.dailyGoal,
            p_activity_amount: day.activityAmount,
            p_earned_seconds: day.earnedSeconds,
            p_streak_days: day.streakDays,
            p_is_final: day.isFinal,
          });
          if (error) rpcError(error);
          // A set-returning scalar function comes back as plain values, or as one-key rows
          // on older PostgREST versions.
          for (const entry of (data as unknown[] | null) ?? []) {
            const id = typeof entry === "string"
              ? entry
              : Object.values(entry as Record<string, string>)[0];
            if (id) recipients.add(id);
          }
        }
        await notify(client, [...recipients], "missed_goal", actor);
        return json({ recorded: days.length, notified: recipients.size });
      }

      case "send": {
        const actor = await requireProfile(client, user.id);
        const friendId = validateUUID(body.friend_id, "friend_id");
        const kind = validateSendKind(body.kind);
        const { data, error } = await client.rpc("social_send", {
          p_user_id: user.id,
          p_friend_id: friendId,
          p_kind: kind,
          p_today: validateDay(body.today),
        });
        if (error) rpcError(error);
        if (data === true) await notify(client, [friendId], kind, actor);
        return json({ sent: data === true });
      }

      case "create_squad": {
        const { data, error } = await client.rpc("social_create_squad", {
          p_user_id: user.id,
          p_name: validateSquadName(body.name),
        });
        if (error) rpcError(error);
        return json({ squad: { id: data.id, name: data.name, inviteCode: data.invite_code } }, 201);
      }

      case "join_squad": {
        const { data, error } = await client.rpc("social_join_squad", {
          p_user_id: user.id,
          p_invite_code: normalizeInviteCode(body.invite_code),
        });
        if (error) rpcError(error);
        return json({ squad: { id: data.id, name: data.name, inviteCode: data.invite_code } });
      }

      case "leave_squad": {
        const { error } = await client.rpc("social_leave_squad", {
          p_user_id: user.id,
          p_squad_id: validateUUID(body.squad_id, "squad_id"),
        });
        if (error) rpcError(error);
        return json({ left: true });
      }

      case "mark_read": {
        const { error } = await client.from("social_events")
          .update({ read_at: new Date().toISOString() })
          .eq("recipient_id", user.id).is("read_at", null);
        if (error) throw error;
        return json({ marked: true });
      }
    }
  } catch (error) {
    return errorResponse(error);
  }
});
