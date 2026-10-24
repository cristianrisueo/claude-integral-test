// What the page shows: the health check is pending, or one of its outcomes.
export type HealthState =
  | "checking"
  | "ok"
  | "database-unreachable"
  | "api-unreachable";

export async function checkHealth(): Promise<Exclude<HealthState, "checking">> {
  throw new Error("not implemented");
}
