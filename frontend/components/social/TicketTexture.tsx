import { ProtoTeamLogo } from "./ProtoImages";

/** Decorative weekly-slate treatment for multi-pick prompt heroes. */
export function TicketTexture({ pickCount, teamCodes }: { pickCount: number; teamCodes: string[] }) {
  return (
    <div aria-hidden className="absolute inset-0 overflow-hidden bg-[radial-gradient(circle_at_78%_38%,rgb(232_227_214/0.1),transparent_25%),linear-gradient(112deg,rgb(25_28_24),rgb(17_19_17)_55%)]">
      <div className="absolute inset-y-0 right-[31%] border-l border-dashed border-fg/25" />
      <div className="absolute inset-x-0 top-1/2 border-t border-dashed border-fg/20" />
      <div className="absolute right-[calc(31%_-_12px)] top-1/2 h-6 w-6 -translate-y-1/2 rounded-full bg-surface" />
      <span className="absolute right-[calc(31%_+_3rem)] top-1/2 -translate-y-1/2 font-slab text-[7rem] leading-none text-fg/[0.06] sm:text-[12rem] lg:text-[16rem]">{String(pickCount).padStart(2, "0")}</span>
      <div className="absolute right-6 bottom-6 hidden max-w-[25rem] items-center justify-end -space-x-3 sm:flex">
        {teamCodes.slice(0, 8).map((code) => <span key={code} className="flex h-12 w-12 items-center justify-center rounded-full border border-fg/15 bg-surface/80 p-2 backdrop-blur-sm"><ProtoTeamLogo code={code} className="h-full w-full" /></span>)}
      </div>
      <span className="absolute right-7 top-7 font-mono text-[10px] tracking-[0.32em] text-fg-muted">WEEKLY SLATE / {pickCount}</span>
    </div>
  );
}
