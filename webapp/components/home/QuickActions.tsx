import { ArrowRight, Gamepad2, Users } from "lucide-react";
import Link from "next/link";

import type { RoomSummary } from "@/components/home/CurrentRoom";
import { DashboardRail } from "@/components/foundation/ui-kit/DashboardRail";

export function QuickActions({ room }: { room: RoomSummary | null }) {
  return (
    <DashboardRail
      headingId="quick-actions-heading"
      eyebrow="Make a move"
      title="Quick actions"
      note="More ways to play will land here as Ball Party grows."
    >
      <div className="mt-4 border-t border-line">
        {room ? <Action href={`/lobby/${room.code}`} icon={Users} label="Return to room" detail="Pick up where you left off" featured /> : null}
        <Action href="/party" icon={Users} label="Start a party" detail="Start a room and invite friends" featured={!room} />
        <Action href="/solo" icon={Gamepad2} label="Play solo" detail="Pick up a game anytime" />
      </div>
    </DashboardRail>
  );
}

function Action({ href, icon: Icon, label, detail, featured = false }: { href: string; icon: typeof Users; label: string; detail: string; featured?: boolean }) {
  return (
    <Link href={href} className={`group flex items-center gap-3 border-b border-line px-1 py-3.5 transition-colors last:border-b-0 hover:bg-surface ${featured ? "text-fg" : "text-fg-muted hover:text-fg"} focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg`}>
      <span className={`flex h-8 w-8 shrink-0 items-center justify-center ${featured ? "bg-fg text-surface" : "bg-surface text-fg-muted ring-1 ring-line ring-inset"}`}><Icon aria-hidden className="h-4 w-4" strokeWidth={1.7} /></span>
      <span className="min-w-0 flex-1">
        <span className="block type-label font-semibold">{label}</span>
        <span className="mt-0.5 block truncate text-xs text-fg-muted">{detail}</span>
      </span>
      <ArrowRight aria-hidden className="h-4 w-4 shrink-0 opacity-0 transition-opacity group-hover:opacity-100" strokeWidth={1.8} />
    </Link>
  );
}
