import { defineConfig, devices } from "@playwright/test";

// The suite targets BASE_URL: the local stack by default, the live site when
// verify.yml sets it.
export default defineConfig({
  testDir: "./tests",
  forbidOnly: !!process.env.CI,
  retries: 0,
  reporter: process.env.CI ? [["list"], ["html", { open: "never" }]] : "list",
  use: {
    baseURL: process.env.BASE_URL ?? "http://localhost:3000",
    trace: "retain-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
