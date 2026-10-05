import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";

import { Field, Input, Textarea } from "./Input";

describe("Input", () => {
  it.each([
    ["dark", "bg-surface"],
    ["well", "bg-surface-raised"],
    ["panel", "bg-panel-shade"],
  ] as const)("renders the %s surface", (variant, surface) => {
    render(<Input variant={variant} aria-label="Name" />);

    expect(screen.getByLabelText("Name")).toHaveClass(surface);
  });

  it("passes native props through", async () => {
    render(<Input aria-label="Email" type="email" name="email" required />);

    const input = screen.getByLabelText("Email");
    await userEvent.type(input, "a@b.co");

    expect(input).toHaveAttribute("type", "email");
    expect(input).toBeRequired();
    expect(input).toHaveValue("a@b.co");
  });
});

describe("Textarea", () => {
  it("renders a multi-line control with the shared surface", () => {
    render(<Textarea aria-label="Message" rows={4} />);

    const area = screen.getByLabelText("Message");
    expect(area.tagName).toBe("TEXTAREA");
    expect(area).toHaveClass("bg-surface");
  });
});

describe("Field", () => {
  it("labels its control, so clicking the label text reaches it", () => {
    render(
      <Field label="Display name">
        <Input name="display_name" />
      </Field>,
    );

    expect(screen.getByLabelText("Display name")).toHaveAttribute("name", "display_name");
  });

  it("shows a hint, and announces an error", () => {
    render(
      <Field label="Password" hint="At least 8 characters" error="Too short">
        <Input type="password" />
      </Field>,
    );

    expect(screen.getByText("At least 8 characters")).toBeInTheDocument();
    expect(screen.getByRole("alert")).toHaveTextContent("Too short");
  });

  it("renders no alert when there is no error", () => {
    render(
      <Field label="Password">
        <Input type="password" />
      </Field>,
    );

    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });
});
