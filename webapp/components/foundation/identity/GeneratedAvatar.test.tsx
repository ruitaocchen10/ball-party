import { render } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { GeneratedAvatar } from "./GeneratedAvatar";

describe("GeneratedAvatar", () => {
  it("keeps a player's generated avatar stable across renders", () => {
    const first = normalize(render(<GeneratedAvatar name="Avery Jones" size={40} />).container.innerHTML);
    const second = normalize(render(<GeneratedAvatar name="Avery Jones" size={40} />).container.innerHTML);

    expect(second).toBe(first);
  });
});

// React's useId is intentionally instance-specific; avatar artwork isn't.
function normalize(markup: string) {
  return markup.replaceAll(/_r_\d+_/g, "avatar-id");
}
