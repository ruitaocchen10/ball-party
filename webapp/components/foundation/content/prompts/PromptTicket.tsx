import type { ComponentPropsWithoutRef } from "react";

/** Shared ticket-stub silhouette used for a prompt preview, answer, or result. */
export const PROMPT_TICKET_CUT_CORNERS = {
  clipPath: "polygon(24px 0, 100% 0, 100% calc(100% - 14px), calc(100% - 24px) 100%, 0 100%, 0 14px)",
};

export function PromptTicket({ children, className = "", style, ...props }: ComponentPropsWithoutRef<"div">) {
  return (
    <div
      {...props}
      style={{
        ...PROMPT_TICKET_CUT_CORNERS,
        backgroundImage: "radial-gradient(circle at 50% -15%, rgb(255 253 247 / 0.09), transparent 46%), repeating-linear-gradient(90deg, transparent 0, transparent calc(20% - 1px), rgb(255 253 247 / 0.035) calc(20% - 1px), rgb(255 253 247 / 0.035) 20%)",
        ...style,
      }}
      className={`relative overflow-hidden bg-surface text-fg shadow-[0_8px_18px_rgb(0_0_0/0.2)] ${className}`}
    >
      {children}
    </div>
  );
}
