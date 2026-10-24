// What the page shows: the health check is pending, or one of its outcomes.
export type HealthState =
  | "checking"
  | "ok"
  | "database-unreachable"
  | "api-unreachable";

function hasBody(body: unknown, status: string, database: string): boolean {
  return (
    typeof body === "object" &&
    body !== null &&
    "status" in body &&
    "database" in body &&
    body.status === status &&
    body.database === database
  );
}

// checkHealth calls the API on the page's own origin. Only the two bodies the
// API sends count as an answer from it; anything else, such as a failed
// request or a 502 page from a proxy, means the API is unreachable.
export async function checkHealth(): Promise<Exclude<HealthState, "checking">> {
  try {
    const response = await fetch("/api/health");
    const body: unknown = await response.json();
    if (response.status === 200 && hasBody(body, "ok", "ok")) return "ok";
    if (response.status === 503 && hasBody(body, "unavailable", "unreachable")) {
      return "database-unreachable";
    }
  } catch {
    // A failed request or a body that is not JSON: the API is unreachable.
  }
  return "api-unreachable";
}
