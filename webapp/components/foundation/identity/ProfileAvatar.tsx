"use client";

import { AnimatePresence, motion } from "motion/react";
import { useState } from "react";

import { fade } from "@/lib/foundation/ui-kit/motion";
import { GeneratedAvatar } from "./GeneratedAvatar";

export function ProfileAvatar({ name, avatarUrl, size = 80 }: { name: string; avatarUrl: string | null; size?: number }) {
  const [imageFailed, setImageFailed] = useState(false);
  const showImage = avatarUrl && !imageFailed;

  return (
    <AnimatePresence mode="wait">
      {showImage ? (
        // Avatar URLs are user-provided hostnames, so Next's allowlisted image
        // optimizer cannot be used here. An error crossfades back to initials.
        // (motion.img isn't recognized as a plain <img> by the no-img-element
        // rule, so no eslint-disable is needed here the way a bare <img> would.)
        <motion.img
          key="image"
          src={avatarUrl}
          alt=""
          onError={() => setImageFailed(true)}
          variants={fade}
          initial="initial"
          animate="animate"
          exit="exit"
          style={{ width: size, height: size }}
          className="shrink-0 rounded-full border-4 border-fg object-cover shadow-card"
        />
      ) : (
        <motion.div
          key="initials"
          aria-hidden
          variants={fade}
          initial="initial"
          animate="animate"
          exit="exit"
          style={{ width: size, height: size }}
          className="grid shrink-0 place-items-center rounded-full border-4 border-fg bg-hidden font-slab text-2xl text-fg shadow-card"
        >
          <GeneratedAvatar name={name} size={size} />
        </motion.div>
      )}
    </AnimatePresence>
  );
}
