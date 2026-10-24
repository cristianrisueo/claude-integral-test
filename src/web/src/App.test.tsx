import { render, screen } from "@testing-library/react";
import { expect, it, vi } from "vitest";
import App from "./App";

function stubFetch(status: number, body: string, contentType = "application/json") {
  const fetch = vi.fn(
    async () => new Response(body, { status, headers: { "Content-Type": contentType } }),
  );
  vi.stubGlobal("fetch", fetch);
  return fetch;
}

it("shows checking while the request is pending", () => {
  vi.stubGlobal("fetch", vi.fn(() => new Promise<Response>(() => {})));

  render(<App />);

  expect(screen.getByText("Checking…")).toBeInTheDocument();
});

it("shows API and database ok", async () => {
  const fetch = stubFetch(200, '{"status":"ok","database":"ok","version":"dev"}');

  render(<App />);

  expect(await screen.findByText("API: ok")).toBeInTheDocument();
  expect(screen.getByText("Database: ok")).toBeInTheDocument();
  expect(screen.queryByText("Checking…")).not.toBeInTheDocument();
  expect(fetch).toHaveBeenCalledWith("/api/health");
});

it("shows database unreachable on 503", async () => {
  stubFetch(503, '{"status":"unavailable","database":"unreachable","version":"dev"}');

  render(<App />);

  expect(await screen.findByText("API: ok")).toBeInTheDocument();
  expect(screen.getByText("Database: unreachable")).toBeInTheDocument();
});

it("shows API unreachable when the request fails", async () => {
  vi.stubGlobal("fetch", vi.fn(async () => Promise.reject(new TypeError("Failed to fetch"))));

  render(<App />);

  expect(await screen.findByText("API: unreachable")).toBeInTheDocument();
  expect(screen.getByText("Database: unknown")).toBeInTheDocument();
});

it("shows API unreachable on an unexpected response", async () => {
  stubFetch(502, "<html><body>502 Bad Gateway</body></html>", "text/html");

  render(<App />);

  expect(await screen.findByText("API: unreachable")).toBeInTheDocument();
  expect(screen.getByText("Database: unknown")).toBeInTheDocument();
});
