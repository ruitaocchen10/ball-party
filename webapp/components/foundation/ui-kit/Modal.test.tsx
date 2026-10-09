import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { createRef } from "react";
import { describe, expect, it, vi } from "vitest";

import { Modal, ModalTitle } from "./Modal";

function setup(props: Partial<React.ComponentProps<typeof Modal>> = {}) {
  const onClose = vi.fn();
  render(
    <Modal onClose={onClose} closeLabel="Close thing" {...props}>
      <ModalTitle>Thing</ModalTitle>
      <input aria-label="First field" />
    </Modal>,
  );
  return onClose;
}

describe("Modal", () => {
  it("is a dialog named by its title", () => {
    setup();

    expect(screen.getByRole("dialog", { name: "Thing" })).toBeInTheDocument();
  });

  it("closes on Escape", async () => {
    const onClose = setup();

    await userEvent.keyboard("{Escape}");

    expect(onClose).toHaveBeenCalledOnce();
  });

  it("closes from the close button", async () => {
    const onClose = setup();

    await userEvent.click(screen.getByRole("button", { name: "Close thing" }));

    expect(onClose).toHaveBeenCalledOnce();
  });

  it("omits the close button when the content supplies its own", () => {
    setup({ closeButton: false });

    expect(screen.queryByRole("button", { name: "Close thing" })).not.toBeInTheDocument();
  });

  it("focuses the close button by default", () => {
    setup();

    expect(screen.getByRole("button", { name: "Close thing" })).toHaveFocus();
  });

  it("focuses initialFocusRef instead when given", () => {
    const ref = createRef<HTMLElement>();
    render(
      <Modal onClose={vi.fn()} closeLabel="Close thing" initialFocusRef={ref}>
        <ModalTitle>Thing</ModalTitle>
        <input aria-label="First field" ref={ref as React.RefObject<HTMLInputElement>} />
      </Modal>,
    );

    expect(screen.getByLabelText("First field")).toHaveFocus();
  });
});
