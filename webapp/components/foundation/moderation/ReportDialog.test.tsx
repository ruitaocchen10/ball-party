import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

const refresh = vi.fn();
vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh }) }));
vi.mock("@/lib/supabase/client", () => ({ createClient: () => ({}) }));
vi.mock("@/lib/foundation/moderation/reports", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/lib/foundation/moderation/reports")>()),
  sendReport: vi.fn(),
}));

import { sendReport } from "@/lib/foundation/moderation/reports";
import { ReportDialog } from "./ReportDialog";

describe("ReportDialog", () => {
  beforeEach(() => {
    refresh.mockClear();
    vi.mocked(sendReport).mockReset();
  });

  it("will not send until a reason is picked", () => {
    render(<ReportDialog target={{ kind: "take", takeId: "t1" }} subject="this take" onClose={vi.fn()} />);
    expect(screen.getByRole("button", { name: "Send report" })).toBeDisabled();
  });

  it("sends the reason and note, confirms, and refreshes the page on close", async () => {
    vi.mocked(sendReport).mockResolvedValue(null);
    const onClose = vi.fn();
    const user = userEvent.setup();
    render(<ReportDialog target={{ kind: "take", takeId: "t1" }} subject="this take" onClose={onClose} refreshOnSent />);

    await user.click(screen.getByLabelText("Harassment or bullying"));
    await user.type(screen.getByRole("textbox"), "targeting me");
    await user.click(screen.getByRole("button", { name: "Send report" }));

    expect(await screen.findByText("Report sent")).toBeInTheDocument();
    expect(sendReport).toHaveBeenCalledWith(expect.anything(), { kind: "take", takeId: "t1" }, { reason: "harassment", details: "targeting me" });

    await user.click(screen.getByRole("button", { name: "Done" }));
    expect(refresh).toHaveBeenCalled();
    expect(onClose).toHaveBeenCalled();
  });

  it("shows the server's refusal and stays open", async () => {
    vi.mocked(sendReport).mockResolvedValue("Create an account to report.");
    const user = userEvent.setup();
    render(<ReportDialog target={{ kind: "profile", profileId: "u1" }} subject="Sam's profile" onClose={vi.fn()} />);

    await user.click(screen.getByLabelText("Spam"));
    await user.click(screen.getByRole("button", { name: "Send report" }));

    await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("Create an account to report."));
    expect(screen.getByRole("button", { name: "Send report" })).toBeEnabled();
  });
});
