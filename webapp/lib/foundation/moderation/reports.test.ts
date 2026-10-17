import { describe, expect, it, vi } from "vitest";

import { REPORT_REASONS, reasonLabel, reportErrorMessage, sendReport } from "./reports";

describe("reportErrorMessage", () => {
  it("words the server's refusals", () => {
    expect(reportErrorMessage("account_required")).toBe("Create an account to report.");
    expect(reportErrorMessage("cannot_report_self")).toBe("You can't report your own take.");
  });

  it("falls back for anything else", () => {
    expect(reportErrorMessage("boom")).toBe("Couldn't send that. Try again.");
    expect(reportErrorMessage(undefined)).toBe("Couldn't send that. Try again.");
  });
});

describe("reasonLabel", () => {
  it("labels every reason the form offers", () => {
    for (const { value, label } of REPORT_REASONS) expect(reasonLabel(value)).toBe(label);
  });
});

describe("sendReport", () => {
  function client(error: { message: string } | null = null) {
    const rpc = vi.fn().mockResolvedValue({ error });
    return { rpc, supabase: { rpc } as never };
  }

  it("reports a take, trimming empty details away", async () => {
    const { rpc, supabase } = client();
    expect(await sendReport(supabase, { kind: "take", takeId: "t1" }, { reason: "spam", details: "  " })).toBeNull();
    expect(rpc).toHaveBeenCalledWith("report_take", { p_comment_id: "t1", p_reason: "spam", p_details: undefined });
  });

  it("reports a profile with its details", async () => {
    const { rpc, supabase } = client();
    await sendReport(supabase, { kind: "profile", profileId: "u1" }, { reason: "hate", details: " rude name " });
    expect(rpc).toHaveBeenCalledWith("report_profile", { p_user_id: "u1", p_reason: "hate", p_details: "rude name" });
  });

  it("returns the server's refusal as a message", async () => {
    const { supabase } = client({ message: "account_required" });
    expect(await sendReport(supabase, { kind: "take", takeId: "t1" }, { reason: "spam", details: "" })).toBe(
      "Create an account to report.",
    );
  });
});
