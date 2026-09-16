import {
  createClient,
  type SupabaseClient,
  type User,
} from "npm:@supabase/supabase-js@2.116.0";
import { env } from "./config.ts";
import { HttpError } from "./response.ts";

export function adminClient(): SupabaseClient {
  return createClient(env.supabaseUrl(), env.secretKey(), {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

export async function requireUser(request: Request): Promise<User> {
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) {
    throw new HttpError(
      401,
      "unauthorized",
      "A bearer access token is required",
    );
  }
  const token = authorization.slice(7);
  const client = createClient(env.supabaseUrl(), env.publishableKey(), {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) {
    throw new HttpError(401, "unauthorized", "Invalid or expired access token");
  }
  return data.user;
}

export async function cleanupExpired(client: SupabaseClient): Promise<void> {
  const { error } = await client.rpc("cleanup_expired_study_sessions");
  if (error) throw error;
}
