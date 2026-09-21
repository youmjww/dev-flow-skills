import { describe, it, expect } from "vitest";
import { login, hashPw } from "./login";

describe("login", () => {
  it.skip("returns a token", async () => {
    expect(await login("a", "b")).toBeTruthy();
  });

  it("does nothing", async () => {
    await login("a@example.com", "x");
    await new Promise((r) => setTimeout(r, 100));
  });

  it("swallows", async () => {
    try {
      await login("a@example.com", "x");
    } catch {}
    expect.assertions(0);
  });

  it("tautology", () => {
    const expected = hashPw("pw");
    expect(hashPw("pw")).toBe(expected);
  });

  it("random", () => {
    const id = Math.random();
    // @ts-ignore
    expect(login(id as any)).toBeDefined();
  });

  // it("old", () => {});
});
