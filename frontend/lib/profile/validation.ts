import { DISPLAY_NAME_MAX, DISPLAY_NAME_MIN } from "@/lib/auth/types";

export type ProfileUpdate = { displayName: string; avatarUrl: string | null };
export type ProfileUpdateValidation = ProfileUpdate | { error: string };

export function validateProfileUpdate(displayNameInput: string, avatarUrlInput: string): ProfileUpdateValidation {
  const displayName = displayNameInput.trim();
  const avatarUrl = avatarUrlInput.trim();

  if (displayName.length < DISPLAY_NAME_MIN || displayName.length > DISPLAY_NAME_MAX) {
    return { error: `Display name must be ${DISPLAY_NAME_MIN}–${DISPLAY_NAME_MAX} characters.` };
  }

  if (avatarUrl) {
    try {
      const url = new URL(avatarUrl);
      if (url.protocol !== "http:" && url.protocol !== "https:") throw new Error("unsupported protocol");
    } catch {
      return { error: "Avatar URL must start with http:// or https://." };
    }
  }

  return { displayName, avatarUrl: avatarUrl || null };
}
