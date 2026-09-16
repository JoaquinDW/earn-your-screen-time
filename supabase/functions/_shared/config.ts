export function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

function namedKey(jsonName: string, legacyName: string): string {
  const values = Deno.env.get(jsonName);
  if (values) {
    const parsed = JSON.parse(values) as Record<string, string>;
    const key = parsed.default ?? Object.values(parsed)[0];
    if (key) return key;
  }
  return requiredEnv(legacyName);
}

export const env = {
  supabaseUrl: () => requiredEnv("SUPABASE_URL"),
  publishableKey: () =>
    namedKey("SUPABASE_PUBLISHABLE_KEYS", "SUPABASE_PUBLISHABLE_KEY"),
  secretKey: () => namedKey("SUPABASE_SECRET_KEYS", "SUPABASE_SECRET_KEY"),
  openAIKey: () => requiredEnv("OPENAI_API_KEY"),
  openAIModel: () =>
    Deno.env.get("OPENAI_MODEL")?.trim() || "gpt-4o-mini-2024-07-18",
  revenueCatWebhookSecret: () => requiredEnv("REVENUECAT_WEBHOOK_SECRET"),
  revenueCatAPIKey: () =>
    Deno.env.get("REVENUECAT_SECRET_API_KEY")?.trim() || null,
  revenueCatEntitlement: () =>
    Deno.env.get("REVENUECAT_ENTITLEMENT_ID")?.trim() ||
    "Earn your Screen Time Pro",
  revenueCatCacheSeconds: () => {
    const parsed = Number(Deno.env.get("REVENUECAT_CACHE_SECONDS") || "300");
    return Number.isFinite(parsed) && parsed >= 0 ? parsed : 300;
  },
};
