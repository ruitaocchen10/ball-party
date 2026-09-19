/**
 * A column's heading: title, a hairline to fill the rest of the row, and a
 * status line flush right.
 *
 * Originally lived inline in app/page.tsx, back when Play, Solo and Social
 * were all subsections of one page and this was always an `<h2>`. Now that
 * Solo and Social are pages of their own, `as` lets the same visual treatment
 * serve as a page's one `<h1>` there while staying an `<h2>` for Play, which
 * is still a subsection of the Party page.
 */
export function ColumnHead({
  id,
  title,
  meta,
  as: Heading = "h2",
}: {
  id: string;
  title: string;
  meta: string;
  as?: "h1" | "h2";
}) {
  return (
    <div className="mb-4 flex items-baseline gap-3.5">
      <Heading id={id} className="font-slab text-base leading-none uppercase sm:text-lg">
        {title}
      </Heading>
      <span aria-hidden className="h-px flex-1 bg-line" />
      <span className="font-mono text-[9px] tracking-[0.15em] text-fg-muted uppercase">
        {meta}
      </span>
    </div>
  );
}
