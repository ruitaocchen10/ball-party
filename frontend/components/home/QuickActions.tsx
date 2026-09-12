import { ArrowRight, Gamepad2, Users } from "lucide-react";
import Link from "next/link";

import type { RoomSummary } from "@/components/home/CurrentRoom";

export function QuickActions({ room }: { room: RoomSummary | null }) {
  return (
    <aside aria-labelledby="quick-actions-heading" className="sticky top-[92px]">
      <div className="border border-line bg-surface-raised p-4 shadow-well">
        <p className="font-mono text-[10px] font-semibold tracking-[0.15em] text-hidden-text uppercase">Make a move</p>
        <h2 id="quick-actions-heading" className="mt-1 font-slab text-[27px] leading-none uppercase">Quick actions</h2>
        <div className="mt-4 border-t border-line">
          {room ? <Action href={`/lobby/${room.code}`} icon={Users} label="Return to room" detail={room.code} featured /> : null}
          <Action href="/party" icon={Users} label="Start a party" detail="Create or join a room" featured={!room} />
          <Action href="/solo" icon={Gamepad2} label="Play solo" detail="Pick up a game anytime" />
        </div>
      </div>
      <p className="px-1 pt-3 font-mono text-[9px] leading-4 tracking-[0.08em] text-fg-muted uppercase">More ways to play will land here as Ball Party grows.</p>
    </aside>
  );
}

function Action({ href, icon: Icon, label, detail, featured = false }: { href: string; icon: typeof Users; label: string; detail: string; featured?: boolean }) {
  return (
    <Link href={href} className={`group flex items-center gap-3 border-b border-line px-1 py-3.5 transition-colors last:border-b-0 hover:bg-surface ${featured ? "text-fg" : "text-fg-muted hover:text-fg"} focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel`}>
      <span className={`flex h-8 w-8 shrink-0 items-center justify-center ${featured ? "bg-panel text-panel-fg" : "bg-surface text-fg-muted ring-1 ring-line ring-inset"}`}><Icon aria-hidden className="h-4 w-4" strokeWidth={1.7} /></span>
      <span className="min-w-0 flex-1">
        <span className="block font-mono text-[10px] font-semibold tracking-[0.08em] uppercase">{label}</span>
        <span className="mt-0.5 block truncate text-xs text-fg-muted">{detail}</span>
      </span>
      <ArrowRight aria-hidden className="h-4 w-4 shrink-0 opacity-0 transition-opacity group-hover:opacity-100" strokeWidth={1.8} />
    </Link>
  );
}
