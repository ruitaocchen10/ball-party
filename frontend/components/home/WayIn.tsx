/** One of the two home-screen panels. `lit` is the cream one — there is only ever one. */
export function WayIn({
  kicker,
  title,
  body,
  lit = false,
  children,
}: {
  kicker: string;
  title: string;
  body: string;
  lit?: boolean;
  children: React.ReactNode;
}) {
  return (
    <div
      className={`flex flex-col rounded-card p-4 sm:p-[18px] ${
        lit ? "bg-panel text-panel-fg shadow-card" : "bg-surface-raised ring-1 ring-line ring-inset"
      }`}
    >
      <p
        className={`font-mono text-[10px] tracking-[0.16em] uppercase ${
          lit ? "text-hidden-ink" : "text-hidden-text"
        }`}
      >
        {kicker}
      </p>
      <h3 className="mt-2.5 font-slab text-xl leading-none -skew-x-7 uppercase sm:text-[22px]">
        {title}
      </h3>
      <p className={`mt-2.5 text-[13.5px] leading-[1.5] ${lit ? "text-[#4c4739]" : "text-[#a5a29c]"}`}>
        {body}
      </p>

      {/* Pinned to the bottom so the two controls line up when the copy above
          them wraps to different heights. */}
      <div className="mt-4 pt-1 sm:mt-auto">{children}</div>
    </div>
  );
}
