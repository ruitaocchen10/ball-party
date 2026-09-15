"use client";

import { AnimatePresence, motion } from "motion/react";
import { useActionState, useState } from "react";

import { type ProfileUpdateState, updateProfile } from "@/app/profile/actions";
import { AnimatedMessage } from "@/components/foundation/ui-kit/AnimatedMessage";
import { expandCollapse } from "@/lib/foundation/ui-kit/motion";
import { createClient } from "@/lib/supabase/client";

const EMPTY_PROFILE_UPDATE_STATE: ProfileUpdateState = { error: null, saved: false };

// Keeps an accidental multi-megapixel phone photo from tying up the upload
// and the eventual page load; comfortably above what an avatar needs.
const MAX_AVATAR_BYTES = 5 * 1024 * 1024;

export function ProfileEditor({
  displayName,
  avatarUrl,
  userId,
}: {
  displayName: string;
  avatarUrl: string | null;
  userId: string;
}) {
  const [editing, setEditing] = useState(false);
  const [state, formAction, pending] = useActionState(updateProfile, EMPTY_PROFILE_UPDATE_STATE);
  const [avatar, setAvatar] = useState(avatarUrl ?? "");
  const [urlMode, setUrlMode] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);

  // Uploads straight to Storage from the browser rather than routing the
  // file through a server action — avoids base64-inflating an image through
  // FormData, and the `avatars` bucket's RLS policies (see migration 0070)
  // already restrict a write to the signed-in user's own `{userId}/` prefix,
  // so there's no server-side gate this would bypass.
  async function handleFileChange(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = ""; // let the same file be re-picked after an error
    if (!file) return;

    if (!file.type.startsWith("image/")) {
      setUploadError("Choose an image file.");
      return;
    }
    if (file.size > MAX_AVATAR_BYTES) {
      setUploadError("Image must be under 5 MB.");
      return;
    }

    setUploadError(null);
    setUploading(true);

    // A stable, extension-qualified path so a re-upload overwrites the
    // previous file (via `upsert`) instead of orphaning it in the bucket.
    const extension = file.name.split(".").pop()?.toLowerCase().replace(/[^a-z0-9]/g, "") || "jpg";
    const path = `${userId}/avatar.${extension}`;

    const supabase = createClient();
    const { error } = await supabase.storage
      .from("avatars")
      .upload(path, file, { upsert: true, cacheControl: "3600" });

    setUploading(false);
    if (error) {
      setUploadError("Upload failed. Please try again.");
      return;
    }

    const { data } = supabase.storage.from("avatars").getPublicUrl(path);
    // Cache-bust: the URL itself doesn't change across an upsert, so without
    // this the <img> (and any browser cache) would keep showing the old file.
    setAvatar(`${data.publicUrl}?t=${Date.now()}`);
  }

  // The trigger button and the form are two different elements, not one
  // panel that grows — AnimatePresence + a shared height/opacity variant
  // (`expandCollapse`, see lib/motion.ts) crossfades between them instead of
  // the instant swap this used to be.
  return (
    <AnimatePresence mode="wait" initial={false}>
      {editing ? (
        <motion.form
          key="form"
          action={formAction}
          variants={expandCollapse}
          initial="initial"
          animate="animate"
          exit="exit"
          className="w-full overflow-hidden rounded-card bg-surface-raised p-4 shadow-well sm:w-[360px]"
        >
          <p className="font-mono text-[10px] tracking-[0.14em] text-fg-muted uppercase">Edit profile</p>
          <label className="mt-3 block font-mono text-[10px] tracking-[0.12em] text-fg-muted uppercase">
            Display name
            <input
              name="display_name"
              defaultValue={displayName}
              minLength={2}
              maxLength={16}
              required
              className="mt-1.5 block w-full border border-line bg-surface px-3 py-2.5 font-sans text-sm text-fg outline-none focus:border-panel"
            />
          </label>
          <div className="mt-3">
            <span className="block font-mono text-[10px] tracking-[0.12em] text-fg-muted uppercase">
              Avatar image <span className="normal-case tracking-normal">(optional)</span>
            </span>
            <div className="mt-1.5 flex items-center gap-2.5">
              <input
                type="file"
                accept="image/*"
                onChange={handleFileChange}
                disabled={uploading}
                className="sr-only"
                id="avatar-file-input"
              />
              <label
                htmlFor="avatar-file-input"
                className="inline-flex cursor-pointer border border-line bg-surface px-3 py-2.5 font-sans text-sm text-fg hover:border-panel aria-disabled:cursor-not-allowed aria-disabled:opacity-60"
                aria-disabled={uploading}
              >
                {uploading ? "Uploading…" : "Choose photo"}
              </label>
              <button
                type="button"
                onClick={() => setUrlMode((value) => !value)}
                className="font-mono text-[10px] tracking-[0.1em] text-fg-muted underline underline-offset-2 hover:text-fg"
              >
                {urlMode ? "cancel" : "or paste a url"}
              </button>
            </div>
            {urlMode ? (
              <input
                type="url"
                value={avatar}
                onChange={(event) => setAvatar(event.target.value)}
                placeholder="https://…"
                className="mt-2 block w-full border border-line bg-surface px-3 py-2.5 font-sans text-sm text-fg outline-none placeholder:text-fg-muted focus:border-panel"
              />
            ) : null}
            <AnimatedMessage role="alert" className="mt-1.5 text-sm text-hidden-text">
              {uploadError}
            </AnimatedMessage>
            <input type="hidden" name="avatar_url" value={avatar} />
          </div>
          <AnimatedMessage role="alert" className="mt-3 text-sm text-hidden-text">
            {state.error}
          </AnimatedMessage>
          <AnimatedMessage role="status" className="mt-3 text-sm text-[#bdc9b9]">
            {state.saved ? "Profile saved." : null}
          </AnimatedMessage>
          <div className="mt-4 flex gap-2.5">
            <button
              type="submit"
              disabled={pending}
              className="bg-panel px-3.5 py-2.5 font-mono text-[10px] font-bold tracking-[0.13em] text-panel-fg uppercase disabled:opacity-60"
            >
              {pending ? "Saving…" : "Save profile"}
            </button>
            <button
              type="button"
              disabled={pending}
              onClick={() => setEditing(false)}
              className="px-3 py-2.5 font-mono text-[10px] font-bold tracking-[0.13em] text-fg-muted uppercase hover:text-fg disabled:opacity-60"
            >
              Cancel
            </button>
          </div>
        </motion.form>
      ) : (
        <motion.button
          key="button"
          type="button"
          onClick={() => setEditing(true)}
          variants={expandCollapse}
          initial="initial"
          animate="animate"
          exit="exit"
          className="bg-hidden px-3.5 py-3 font-mono text-[10px] font-bold tracking-[0.13em] text-white uppercase transition-colors hover:bg-hidden-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel"
        >
          Edit profile
        </motion.button>
      )}
    </AnimatePresence>
  );
}
