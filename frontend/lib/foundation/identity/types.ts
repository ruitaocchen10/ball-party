/**
 * Kept out of `actions.ts` because every export from a `'use server'` module
 * must be an async function.
 */
export type AuthState = {
  error: string | null;
};

export const EMPTY_AUTH_STATE: AuthState = { error: null };

export const DISPLAY_NAME_MIN = 2;
export const DISPLAY_NAME_MAX = 16;
export const PASSWORD_MIN = 8;
