/**
 * `submitFeedback`'s result shape, plus its zero value — split out of
 * actions.ts because a `"use server"` file may only export async functions.
 * `EMPTY_FEEDBACK_STATE` is a plain object, so it has to live somewhere else
 * to be importable from the client component that seeds `useActionState`
 * with it.
 */
export type FeedbackState = { error: string | null; saved: boolean };

export const EMPTY_FEEDBACK_STATE: FeedbackState = { error: null, saved: false };
