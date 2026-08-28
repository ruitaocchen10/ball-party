"use client";

import { AnimatePresence, motion } from "motion/react";
import { useState } from "react";

import { fade } from "@/lib/motion";

export function ProfileAvatar({ name, avatarUrl }: { name: string; avatarUrl: string | null }) {
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
          className="h-20 w-20 shrink-0 rounded-full border-4 border-panel object-cover shadow-card"
        />
      ) : (
        <motion.div
          key="initials"
          aria-hidden
          variants={fade}
          initial="initial"
          animate="animate"
          exit="exit"
          className="grid h-20 w-20 shrink-0 place-items-center rounded-full border-4 border-panel bg-hidden font-slab text-2xl text-panel shadow-card"
        >
          <span className="font-slab-optical-center">{initials(name)}</span>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

function initials(name: string) {
  return (
    name
      .trim()
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((part) => part[0]?.toUpperCase())
      .join("") || "?"
  );
}
