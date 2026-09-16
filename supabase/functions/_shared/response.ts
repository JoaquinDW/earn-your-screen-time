const headers = { "content-type": "application/json; charset=utf-8" };

export function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers });
}

export function errorResponse(error: unknown): Response {
  if (error instanceof HttpError) {
    return json({ error: error.message, code: error.code }, error.status);
  }
  console.error(
    error instanceof Error ? error.message : "Unknown function error",
  );
  return json({ error: "Internal server error", code: "internal_error" }, 500);
}

export class HttpError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

export async function readJson<T>(request: Request): Promise<T> {
  if (
    !request.headers.get("content-type")?.toLowerCase().includes(
      "application/json",
    )
  ) {
    throw new HttpError(
      415,
      "invalid_content_type",
      "Content-Type must be application/json",
    );
  }
  try {
    return await request.json() as T;
  } catch {
    throw new HttpError(400, "invalid_json", "Request body must be valid JSON");
  }
}

export function method(request: Request, allowed: string): void {
  if (request.method !== allowed) {
    throw new HttpError(405, "method_not_allowed", `Use ${allowed}`);
  }
}
