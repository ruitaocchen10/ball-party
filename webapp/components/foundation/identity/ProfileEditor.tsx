"use client";

import { ArrowLeft, Camera } from "lucide-react";
import { useActionState, useEffect, useRef, useState } from "react";

import { type ProfileUpdateState, updateProfile } from "@/app/profile/actions";
import { ProfileAvatar } from "@/components/foundation/identity/ProfileAvatar";
import { AnimatedMessage } from "@/components/foundation/ui-kit/AnimatedMessage";
import { Field, Input } from "@/components/foundation/ui-kit/Input";
import { Modal, ModalTitle } from "@/components/foundation/ui-kit/Modal";
import { createClient } from "@/lib/supabase/client";
import { PresetAvatarPicker } from "./PresetAvatarPicker";

const EMPTY_PROFILE_UPDATE_STATE: ProfileUpdateState = { error: null, saved: false };
const MAX_AVATAR_BYTES = 5 * 1024 * 1024;

type ProfileEditorProps = {
  displayName: string;
  avatarUrl: string | null;
  userId: string;
};

/** The profile header's trigger; editing itself happens in a focused dialog. */
export function ProfileEditor(props: ProfileEditorProps) {
  const [editing, setEditing] = useState(false);
  const trigger = useRef<HTMLButtonElement>(null);
  const restoreFocus = useRef(false);

  useEffect(() => {
    if (!editing && restoreFocus.current) {
      trigger.current?.focus();
      restoreFocus.current = false;
    }
  }, [editing]);

  function close() {
    restoreFocus.current = true;
    setEditing(false);
  }

  return (
    <>
      <button
        ref={trigger}
        type="button"
        onClick={() => setEditing(true)}
        className="bg-hidden px-3.5 py-3 type-label font-bold text-white transition-colors hover:bg-hidden-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel"
      >
        Edit profile
      </button>
      {editing ? <ProfileEditorDialog {...props} onClose={close} /> : null}
    </>
  );
}

function ProfileEditorDialog({ displayName, avatarUrl, userId, onClose }: ProfileEditorProps & { onClose: () => void }) {
  const [state, formAction, pending] = useActionState(updateProfile, EMPTY_PROFILE_UPDATE_STATE);
  const [avatar, setAvatar] = useState(avatarUrl ?? "");
  const [editingPhoto, setEditingPhoto] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [presetUploading, setPresetUploading] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const nameInput = useRef<HTMLInputElement>(null);

  // Uploads straight to Storage from the browser. The avatars bucket's RLS
  // policy limits a write to the signed-in user's own prefix.
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
    const extension = file.name.split(".").pop()?.toLowerCase().replace(/[^a-z0-9]/g, "") || "jpg";
    const path = `${userId}/avatar.${extension}`;
    const supabase = createClient();
    const { error } = await supabase.storage.from("avatars").upload(path, file, { upsert: true, cacheControl: "3600" });

    setUploading(false);
    if (error) {
      setUploadError("Upload failed. Please try again.");
      return;
    }

    const { data } = supabase.storage.from("avatars").getPublicUrl(path);
    setAvatar(`${data.publicUrl}?t=${Date.now()}`);
    setEditingPhoto(false);
  }

  return (
    <Modal onClose={onClose} closeLabel="Close profile editor" initialFocusRef={nameInput}>
      {state.saved ? (
        <div className="pr-10">
          <p className="type-label font-semibold text-hidden-text">Profile updated</p>
          <ModalTitle className="mt-1 font-slab text-3xl uppercase">Looking good.</ModalTitle>
          <p className="mt-2 text-sm text-fg-muted">Your profile changes have been saved.</p>
          <button type="button" onClick={onClose} className="mt-5 bg-panel px-3.5 py-2.5 type-label font-bold text-panel-fg">
            Done
          </button>
        </div>
      ) : editingPhoto ? (
        <ProfilePhotoChooser
          avatarUrl={avatar || null}
          displayName={displayName}
          userId={userId}
          uploading={uploading}
          uploadError={uploadError}
          onBack={() => setEditingPhoto(false)}
          onUpload={handleFileChange}
          onPresetSelected={(url) => {
            setAvatar(url);
            setEditingPhoto(false);
          }}
          onPresetUploadingChange={setPresetUploading}
        />
      ) : (
        <form action={formAction}>
          <div className="pr-10">
            <p className="type-label font-semibold text-hidden-text">Player profile</p>
            <ModalTitle className="mt-1 font-slab text-3xl uppercase">Edit profile</ModalTitle>
          </div>
          <div className="mt-5 pb-5">
            <button
              type="button"
              aria-label="Change profile photo"
              onClick={() => setEditingPhoto(true)}
              className="group relative block rounded-full focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-panel"
            >
              <ProfileAvatar name={displayName} avatarUrl={avatar || null} />
              <span className="absolute right-0 bottom-0 flex h-8 w-8 items-center justify-center rounded-full border-2 border-surface-raised bg-panel text-panel-fg transition-transform group-hover:scale-105">
                <Camera aria-hidden className="h-4 w-4" strokeWidth={1.8} />
              </span>
            </button>
            <input type="hidden" name="avatar_url" value={avatar} />
          </div>
          <Field label="Display name" className="mt-5">
<Input
              ref={nameInput}
              name="display_name"
              defaultValue={displayName}
              minLength={2}
              maxLength={16}
              required
              />
</Field>
          <AnimatedMessage role="alert" className="mt-3 text-sm text-hidden-text">
            {state.error}
          </AnimatedMessage>
          <div className="mt-5 flex gap-2.5">
            <button type="submit" disabled={pending || uploading || presetUploading} className="bg-panel px-3.5 py-2.5 type-label font-bold text-panel-fg disabled:opacity-60">
              {pending ? "Saving…" : "Save profile"}
            </button>
            <button type="button" disabled={pending} onClick={onClose} className="px-3 py-2.5 type-label font-bold text-fg-muted hover:text-fg disabled:opacity-60">
              Cancel
            </button>
          </div>
        </form>
      )}
    </Modal>
  );
}

function ProfilePhotoChooser({
  avatarUrl,
  displayName,
  userId,
  uploading,
  uploadError,
  onBack,
  onUpload,
  onPresetSelected,
  onPresetUploadingChange,
}: {
  avatarUrl: string | null;
  displayName: string;
  userId: string;
  uploading: boolean;
  uploadError: string | null;
  onBack: () => void;
  onUpload: (event: React.ChangeEvent<HTMLInputElement>) => void;
  onPresetSelected: (avatarUrl: string) => void;
  onPresetUploadingChange: (uploading: boolean) => void;
}) {
  return (
    <div>
      <button type="button" onClick={onBack} className="inline-flex items-center gap-1 type-label text-fg-muted hover:text-fg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel">
        <ArrowLeft aria-hidden className="h-3.5 w-3.5" strokeWidth={2} />
        Back to profile
      </button>
      <div className="mt-5 flex items-center gap-4">
        <ProfileAvatar name={displayName} avatarUrl={avatarUrl} />
        <div>
          <p className="type-label font-semibold text-hidden-text">Profile photo</p>
          <ModalTitle className="mt-1 font-slab text-3xl uppercase">Choose your look</ModalTitle>
        </div>
      </div>
      <div className="mt-5">
        <input type="file" accept="image/*" onChange={onUpload} disabled={uploading} className="sr-only" id="avatar-file-input" />
        <label
          htmlFor="avatar-file-input"
          className="flex min-h-12 w-full cursor-pointer items-center justify-center border border-line px-3 type-label font-bold text-fg-muted hover:border-fg-muted hover:text-fg aria-disabled:cursor-not-allowed aria-disabled:opacity-60"
          aria-disabled={uploading}
        >
          {uploading ? "Uploading…" : "Upload from device"}
        </label>
      </div>
      <PresetAvatarPicker userId={userId} onSelect={onPresetSelected} onUploadingChange={onPresetUploadingChange} />
      <AnimatedMessage role="alert" className="mt-2 text-sm text-hidden-text">
        {uploadError}
      </AnimatedMessage>
    </div>
  );
}
