import { describe, it, expect, vi } from "vitest";
import { login } from "./login";

describe("login", () => {
  // TC-001
  it("returns a token for correct credentials", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-01-01"));
    const token = await login("alice@example.com", "correct-horse");
    expect(token).toMatch(/^eyJ/);
  });

  // TC-002
  it.each([["x"], [""]])("rejects password %s", async (pw) => {
    await expect(login("alice@example.com", pw)).rejects.toThrow("INVALID_CREDENTIALS");
  });
});
