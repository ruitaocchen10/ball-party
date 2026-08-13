"use client";

import { useActionState, useState } from "react";

import {
  EMPTY_PROFILE_UPDATE_STATE,
  updateProfile,
} from "@/app/profile/actions";

export function ProfileEditor({ displayName, avatarUrl }: { displayName: string; avatarUrl: string | null }) {
  const [editing, setEditing] = useState(false);
  const [state, formAction, pending] = useActionState(updateProfile, EMPTY_PROFILE_UPDATE_STATE);

  if (!editing) {
    return <button type="button" onClick={() => setEditing(true)} className="rounded-[3px] bg-hidden px-3.5 py-3 font-mono text-[10px] font-bold tracking-[0.13em] text-white uppercase transition-colors hover:bg-hidden-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel">Edit profile</button>;
  }

  return (
    <form action={formAction} className="w-full rounded-card border border-line bg-surface-raised p-4 sm:w-[360px]">
      <p className="font-mono text-[10px] tracking-[0.14em] text-fg-muted uppercase">Edit profile</p>
      <label className="mt-3 block font-mono text-[10px] tracking-[0.12em] text-fg-muted uppercase">Display name
        <input name="display_name" defaultValue={displayName} minLength={2} maxLength={16} required className="mt-1.5 block w-full rounded-[3px] border border-line bg-surface px-3 py-2.5 font-sans text-sm text-fg outline-none focus:border-panel" />
      </label>
      <label className="mt-3 block font-mono text-[10px] tracking-[0.12em] text-fg-muted uppercase">Avatar image URL <span className="normal-case tracking-normal">(optional)</span>
        <input name="avatar_url" type="url" defaultValue={avatarUrl ?? ""} placeholder="https://…" className="mt-1.5 block w-full rounded-[3px] border border-line bg-surface px-3 py-2.5 font-sans text-sm text-fg outline-none placeholder:text-fg-muted focus:border-panel" />
      </label>
      {state.error ? <p role="alert" className="mt-3 text-sm text-hidden-text">{state.error}</p> : null}
      {state.saved ? <p role="status" className="mt-3 text-sm text-[#bdc9b9]">Profile saved.</p> : null}
      <div className="mt-4 flex gap-2.5"><button type="submit" disabled={pending} className="rounded-[3px] bg-panel px-3.5 py-2.5 font-mono text-[10px] font-bold tracking-[0.13em] text-panel-fg uppercase disabled:opacity-60">{pending ? "Saving…" : "Save profile"}</button><button type="button" disabled={pending} onClick={() => setEditing(false)} className="rounded-[3px] px-3 py-2.5 font-mono text-[10px] font-bold tracking-[0.13em] text-fg-muted uppercase hover:text-fg disabled:opacity-60">Cancel</button></div>
    </form>
  );
}
