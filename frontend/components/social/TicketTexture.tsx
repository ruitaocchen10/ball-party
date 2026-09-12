/** Decorative weekly-slate treatment for multi-pick prompt heroes. */
export function TicketTexture({ pickCount }: { pickCount: number }) {
  return (
    <div aria-hidden className="absolute inset-0 overflow-hidden opacity-50">
      <div className="absolute inset-y-0 right-[27%] border-l border-dashed border-fg/25" />
      <div className="absolute inset-x-0 top-[30%] border-t border-dashed border-fg/20" />
      <div className="absolute inset-x-0 top-[66%] border-t border-dashed border-fg/20" />
      <div className="absolute right-[calc(27%_-_12px)] top-[30%] h-6 w-6 -translate-y-1/2 rounded-full bg-surface" />
      <div className="absolute right-[calc(27%_-_12px)] top-[66%] h-6 w-6 -translate-y-1/2 rounded-full bg-surface" />
      <span className="absolute right-8 top-8 font-mono text-[10px] tracking-[0.32em] text-fg-muted">SLATE / {pickCount}</span>
      <span className="absolute right-8 bottom-8 font-mono text-[10px] tracking-[0.32em] text-fg-muted">ADMIT ONE</span>
    </div>
  );
}
