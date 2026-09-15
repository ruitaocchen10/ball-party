import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { createElement, forwardRef, type ReactNode } from "react";
import { afterEach, vi } from "vitest";

afterEach(() => cleanup());

// motion/react (see lib/motion.ts) drives every new transition in the app.
// Its real animations run on rAF-driven timers jsdom doesn't tick, which
// would leave "removed" elements sitting in the DOM well past a test's own
// synchronous assertions (an AnimatePresence exit, in particular, only
// unmounts once its exit animation completes). Replaced here with plain
// passthrough elements that mount/unmount exactly when their conditional
// does — the same instant behavior the CSS-only interactions this replaces
// already had.
const MOTION_ONLY_PROPS = new Set([
  "initial",
  "animate",
  "exit",
  "variants",
  "transition",
  "whileHover",
  "whileTap",
  "whileFocus",
  "whileInView",
  "whileDrag",
  "layout",
  "layoutId",
  "onAnimationComplete",
  "onAnimationStart",
  "drag",
  "dragConstraints",
  "dragElastic",
  "dragMomentum",
]);

function stripMotionProps(props: Record<string, unknown>) {
  const rest: Record<string, unknown> = {};
  for (const key in props) {
    if (!MOTION_ONLY_PROPS.has(key)) rest[key] = props[key];
  }
  return rest;
}

function motionMockFor(Component: unknown) {
  const Mock = forwardRef((props: Record<string, unknown>, ref) =>
    createElement(Component as never, { ...stripMotionProps(props), ref }),
  );
  Mock.displayName = `motion(${String(Component)})`;
  return Mock;
}

// `motion.div`, `motion.button`, etc. must resolve to the *same* component
// reference on every render, the way the real library's are pre-created and
// stable — otherwise React sees a new element type each render and remounts
// the DOM node instead of updating it, wiping out any uncontrolled input
// state (a <select> mid-form, a focused field) along the way. Cached by tag
// for exactly that reason.
const motionTagCache = new Map<string, ReturnType<typeof motionMockFor>>();

const motionMock = new Proxy(motionMockFor, {
  get: (target, tag: string) => {
    if (tag === "create") return target;
    if (!motionTagCache.has(tag)) motionTagCache.set(tag, motionMockFor(tag));
    return motionTagCache.get(tag);
  },
});

vi.mock("motion/react", () => ({
  motion: motionMock,
  m: motionMock,
  AnimatePresence: ({ children }: { children?: ReactNode }) => children ?? null,
  MotionConfig: ({ children }: { children?: ReactNode }) => children ?? null,
}));

// motion's MotionConfig/useReducedMotion reads this in real usage; nothing in
// jsdom implements it. Mocked away above for this app's own components, but
// polyfilled too in case a future test exercises the real library directly.
if (!window.matchMedia) {
  window.matchMedia = (query: string) =>
    ({
      matches: false,
      media: query,
      onchange: null,
      addListener: () => {},
      removeListener: () => {},
      addEventListener: () => {},
      removeEventListener: () => {},
      dispatchEvent: () => false,
    }) as MediaQueryList;
}

// The match screen talks to Postgres directly over supabase-js. The tests drive
// the component through props and assert what it renders, so the client is
// replaced wholesale — see test/factories.ts for the RPC spy the suites use.
vi.mock("@/lib/supabase/client", () => ({
  createClient: () => globalThis.__supabaseMock,
  createRealtimeClient: async () => globalThis.__supabaseMock,
}));

// A server action, reached through Sidebar -> AccountMenu. Importing it for real
// pulls next/headers into jsdom, which throws.
vi.mock("@/lib/auth/actions", () => ({ signOut: vi.fn() }));
vi.mock("@/lib/feedback/actions", () => ({ submitFeedback: vi.fn() }));

// jsdom implements no layout or element scrolling. The board strip scrolls its
// own horizontal rail, so this no-op lets the test assert the public behavior.
if (!HTMLElement.prototype.scrollTo) HTMLElement.prototype.scrollTo = vi.fn();
// The isolated design harness still demonstrates the earlier prototype strip.
if (!Element.prototype.scrollIntoView) Element.prototype.scrollIntoView = vi.fn();

// jsdom implements no pointer capture. Radix's Select (see components/ui/Select.tsx)
// calls these on open/close to route pointer events to its listbox instead of
// whatever's under the cursor; without a polyfill the calls throw and the
// select never opens in a test.
if (!Element.prototype.hasPointerCapture) Element.prototype.hasPointerCapture = () => false;
if (!Element.prototype.setPointerCapture) Element.prototype.setPointerCapture = vi.fn();
if (!Element.prototype.releasePointerCapture) Element.prototype.releasePointerCapture = vi.fn();
