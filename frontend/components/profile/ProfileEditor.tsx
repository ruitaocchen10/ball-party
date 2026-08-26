"use client";

import { AnimatePresence, motion } from "motion/react";
import { useActionState, useState } from "react";

import { type ProfileUpdateState, updateProfile } from "@/app/profile/actions";
import { AnimatedMessage } from "@/components/motion/AnimatedMessage";
import { expandCollapse } from "@/lib/motion";

const EMPTY_PROFILE_UPDATE_STATE: ProfileUpdateState = { error: null, saved: false };

export function ProfileEditor({ displayName, avatarUrl }: { displayName: string; avatarUrl: string | null }) {
  const [editing, setEditing] = useState(false);
  const [state, formAction, pending] = useActionState(updateProfile, EMPTY_PROFILE_UPDATE_STATE);

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
          <label className="mt-3 block font-mono text-[10px] tracking-[0.12em] text-fg-muted uppercase">
            Avatar image URL <span className="normal-case tracking-normal">(optional)</span>
            <input
              name="avatar_url"
              type="url"
              defaultValue={avatarUrl ?? ""}
              placeholder="https://…"
              className="mt-1.5 block w-full border border-line bg-surface px-3 py-2.5 font-sans text-sm text-fg outline-none placeholder:text-fg-muted focus:border-panel"
            />
          </label>
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
