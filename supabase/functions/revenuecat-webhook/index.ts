import { adminClient } from "../_shared/supabase.ts";
import { env } from "../_shared/config.ts";
import {
  entitlementFromWebhookEvent,
  refreshRevenueCatEntitlement,
  saveEntitlement,
} from "../_shared/revenuecat.ts";
import { errorResponse, HttpError, json, method } from "../_shared/response.ts";
import { verifyRevenueCatSignature } from "../_shared/webhook.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

Deno.serve(async (request) => {
  let eventId: string | null = null;
  const client = adminClient();
  try {
    method(request, "POST");
    const rawBody = new Uint8Array(await request.arrayBuffer());
    const signature = request.headers.get("x-revenuecat-webhook-signature") ||
      "";
    if (
      !await verifyRevenueCatSignature(
        rawBody,
        signature,
        env.revenueCatWebhookSecret(),
      )
    ) {
      throw new HttpError(
        401,
        "invalid_signature",
        "Invalid webhook signature",
      );
    }
    let payload: { event?: Record<string, unknown> };
    try {
      payload = JSON.parse(new TextDecoder().decode(rawBody));
    } catch {
      throw new HttpError(
        400,
        "invalid_json",
        "Webhook body must be valid JSON",
      );
    }
    const event = payload.event;
    if (!event) {
      throw new HttpError(400, "invalid_event", "Webhook event is required");
    }
    eventId = typeof event?.id === "string" ? event.id : null;
    const eventType = typeof event?.type === "string" ? event.type : null;
    if (!eventId || !eventType) {
      throw new HttpError(
        400,
        "invalid_event",
        "Webhook event id and type are required",
      );
    }
    const appUserId = typeof event.app_user_id === "string"
      ? event.app_user_id
      : null;
    const environment =
      event.environment === "SANDBOX" || event.environment === "PRODUCTION"
        ? event.environment
        : null;
    const eventTimestamp = typeof event.event_timestamp_ms === "number"
      ? new Date(event.event_timestamp_ms).toISOString()
      : null;
    const { data: claimed, error: claimError } = await client.rpc(
      "claim_revenuecat_webhook_event",
      {
        p_event_id: eventId,
        p_event_type: eventType,
        p_app_user_id: appUserId,
        p_environment: environment,
        p_event_timestamp: eventTimestamp,
      },
    );
    if (claimError) throw claimError;
    if (!claimed) return json({ received: true, duplicate: true });

    const candidateIds = new Set<string>();
    if (appUserId && UUID.test(appUserId)) candidateIds.add(appUserId);
    for (const key of ["aliases", "transferred_from", "transferred_to"]) {
      const values = event[key];
      if (Array.isArray(values)) {
        for (const value of values) {
          if (typeof value === "string" && UUID.test(value)) {
            candidateIds.add(value);
          }
        }
      }
    }
    for (const userId of candidateIds) {
      const refreshed = await refreshRevenueCatEntitlement(client, userId);
      if (!refreshed && userId === appUserId) {
        await saveEntitlement(
          client,
          userId,
          entitlementFromWebhookEvent(event),
        );
      }
    }
    const { error: completeError } = await client.rpc(
      "complete_revenuecat_webhook_event",
      { p_event_id: eventId, p_error: null },
    );
    if (completeError) throw completeError;
    return json({ received: true });
  } catch (error) {
    if (eventId) {
      const message = error instanceof Error
        ? error.message
        : "Unknown webhook failure";
      await client.rpc("complete_revenuecat_webhook_event", {
        p_event_id: eventId,
        p_error: message,
      });
    }
    return errorResponse(error);
  }
});
