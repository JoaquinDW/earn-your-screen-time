/**
 * Sends alerts through Apple Push Notification service with token-based auth (a .p8 key).
 *
 * Push is optional: until APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY and APNS_BUNDLE_ID are
 * set, `apnsConfiguration()` returns null and nothing is sent. Friends still see every event in
 * the app's inbox.
 */
export type APNsConfiguration = {
  keyId: string;
  teamId: string;
  privateKey: string;
  bundleId: string;
};

export type APNsTarget = {
  token: string;
  environment: "sandbox" | "production";
};

export type APNsResult = "sent" | "invalid_token" | "failed";

export function apnsConfiguration(): APNsConfiguration | null {
  const keyId = Deno.env.get("APNS_KEY_ID")?.trim();
  const teamId = Deno.env.get("APNS_TEAM_ID")?.trim();
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY")?.trim();
  const bundleId = Deno.env.get("APNS_BUNDLE_ID")?.trim();
  if (!keyId || !teamId || !privateKey || !bundleId) return null;
  return { keyId, teamId, privateKey, bundleId };
}

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** The PEM body of a .p8 file, which may arrive with literal "\n" sequences from a secret. */
export function pemToDer(pem: string): Uint8Array {
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (character) => character.charCodeAt(0));
}

let cachedToken: { value: string; issuedAt: number; keyId: string } | null = null;

/** Apple accepts a provider token for an hour and rejects refreshing it more than every 20 minutes. */
async function providerToken(configuration: APNsConfiguration): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (
    cachedToken && cachedToken.keyId === configuration.keyId &&
    now - cachedToken.issuedAt < 45 * 60
  ) {
    return cachedToken.value;
  }
  const encoder = new TextEncoder();
  const header = base64url(
    encoder.encode(JSON.stringify({ alg: "ES256", kid: configuration.keyId })),
  );
  const claims = base64url(
    encoder.encode(JSON.stringify({ iss: configuration.teamId, iat: now })),
  );
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(configuration.privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  // WebCrypto returns the raw r || s signature JWS expects.
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      encoder.encode(`${header}.${claims}`),
    ),
  );
  const value = `${header}.${claims}.${base64url(signature)}`;
  cachedToken = { value, issuedAt: now, keyId: configuration.keyId };
  return value;
}

export async function sendPush(
  configuration: APNsConfiguration,
  target: APNsTarget,
  alert: Record<string, unknown>,
  data: Record<string, unknown> = {},
): Promise<APNsResult> {
  const host = target.environment === "production"
    ? "api.push.apple.com"
    : "api.sandbox.push.apple.com";
  try {
    const response = await fetch(`https://${host}/3/device/${target.token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${await providerToken(configuration)}`,
        "apns-topic": configuration.bundleId,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body: JSON.stringify({ aps: { alert, sound: "default" }, ...data }),
    });
    if (response.ok) return "sent";
    const reason = (await response.json().catch(() => ({})) as { reason?: string })
      .reason;
    if (
      response.status === 410 || reason === "BadDeviceToken" ||
      reason === "DeviceTokenNotForTopic"
    ) {
      return "invalid_token";
    }
    console.error(`APNs rejected a push (${response.status} ${reason ?? ""})`);
    return "failed";
  } catch (error) {
    console.error(
      `APNs request failed: ${error instanceof Error ? error.message : "unknown"}`,
    );
    return "failed";
  }
}
