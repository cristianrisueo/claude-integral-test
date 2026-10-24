import { expect, test } from "@playwright/test";

test("page shows API and database ok", async ({ page }) => {
  await page.goto("/");

  await expect(page.getByText("API: ok")).toBeVisible();
  await expect(page.getByText("Database: ok")).toBeVisible();
});

test("GET /api/health answers 200 with database ok", async ({ request }) => {
  const response = await request.get("/api/health");

  expect(response.status()).toBe(200);
  expect(await response.json()).toEqual({ status: "ok", database: "ok", version: "dev" });
});
