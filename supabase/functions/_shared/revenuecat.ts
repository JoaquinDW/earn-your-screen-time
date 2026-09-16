import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { env } from "./config.ts";

type EntitlementState = {
  is_active: boolean;
  product_id: string | null;
  environment: "SANDBOX" | "PRODUCTION" | null;
  expires_at: string | null;
};

function activeAt(expiresAt: string | null): boolean {
  return expiresAt === null || Date.parse(expiresAt) > Date.now();
}

export async function refreshRevenueCatEntitlement(
  client: SupabaseClient,
  userId: string,
): Promise<EntitlementState | null> {
  const apiKey = env.revenueCatAPIKey();
  if (!apiKey) return null;
  const response = await fetch(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}`,
    {
      headers: {
        authorization: `Bearer ${apiKey}`,
        accept: "application/json",
      },
    },
  );
  if (response.status === 404) {
    return saveEntitlement(client, userId, {
      is_active: false,
      product_id: null,
      environment: null,
      expires_at: null,
    });
  }
  if (!response.ok) {
    throw new Error(`RevenueCat refresh failed with ${response.status}`);
  }
  const payload = await response.json() as {
    subscriber?: {
      entitlements?: Record<
        string,
        {
          expires_date?: string | null;
          product_identifier?: string;
          purchase_date?: string;
        }
      >;
    };
  };
  const entitlement = payload.subscriber?.entitlements
    ?.[env.revenueCatEntitlement()];
  const expiresAt = entitlement?.expires_date ?? null;
  return saveEntitlement(client, userId, {
    is_active: Boolean(entitlement) && activeAt(expiresAt),
    product_id: entitlement?.product_identifier ?? null,
    environment: null,
    expires_at: expiresAt,
  });
}

export async function entitlementForUser(
  client: SupabaseClient,
  userId: string,
): Promise<boolean> {
  const entitlementId = env.revenueCatEntitlement();
  const { data, error } = await client.from("user_entitlements").select(
    "is_active,expires_at,last_synced_at",
  )
    .eq("user_id", userId).eq("entitlement_id", entitlementId).maybeSingle();
  if (error) throw error;
  const freshAfter = Date.now() - env.revenueCatCacheSeconds() * 1000;
  if (data && Date.parse(data.last_synced_at) >= freshAfter) {
    return data.is_active && activeAt(data.expires_at);
  }
  try {
    const refreshed = await refreshRevenueCatEntitlement(client, userId);
    if (refreshed) return refreshed.is_active;
  } catch (error) {
    console.error(
      error instanceof Error ? error.message : "RevenueCat refresh failed",
    );
  }
  return Boolean(data?.is_active && activeAt(data.expires_at));
}

export function entitlementFromWebhookEvent(
  event: Record<string, unknown>,
): EntitlementState {
  const expiresMs = typeof event.expiration_at_ms === "number"
    ? event.expiration_at_ms
    : null;
  const expiresAt = expiresMs ? new Date(expiresMs).toISOString() : null;
  const eventType = String(event.type ?? "");
  return {
    is_active: eventType !== "EXPIRATION" && eventType !== "TRANSFER" &&
      activeAt(expiresAt),
    product_id: typeof event.product_id === "string" ? event.product_id : null,
    environment:
      event.environment === "SANDBOX" || event.environment === "PRODUCTION"
        ? event.environment
        : null,
    expires_at: expiresAt,
  };
}

export async function saveEntitlement(
  client: SupabaseClient,
  userId: string,
  state: EntitlementState,
) {
  const row = {
    user_id: userId,
    entitlement_id: env.revenueCatEntitlement(),
    ...state,
    last_synced_at: new Date().toISOString(),
  };
  const { error } = await client.from("user_entitlements").upsert(row, {
    onConflict: "user_id,entitlement_id",
  });
  if (error) throw error;
  return state;
}
