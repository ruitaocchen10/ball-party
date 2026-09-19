import { ArrowLeft } from "lucide-react";
import Link from "next/link";
import type { ReactNode } from "react";

type PageHeaderProps = {
  title: ReactNode;
  eyebrow?: ReactNode;
  description?: ReactNode;
  backHref?: string;
  backLabel?: ReactNode;
};

/** A consistent, compact heading for top-level and detail pages. */
export function PageHeader({
  title,
  eyebrow,
  description,
  backHref,
  backLabel,
}: PageHeaderProps) {
  return (
    <header className="w-full max-w-[760px] border-b border-line pb-4">
      {backHref && backLabel ? (
        <div className="mb-4">
          <Link
            href={backHref}
            className="inline-flex shrink-0 items-center gap-1 border-b border-fg/50 pb-1 font-mono text-[10px] tracking-[0.12em] text-fg uppercase transition-colors hover:border-fg hover:text-fg-muted focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-panel"
          >
            <ArrowLeft className="h-3.5 w-3.5" strokeWidth={2.25} />
            {backLabel}
          </Link>
        </div>
      ) : null}
      {eyebrow ? <p className="font-mono text-[10px] font-semibold tracking-[0.16em] text-hidden-text uppercase">{eyebrow}</p> : null}
      <h1 className="mt-1 font-slab text-[34px] leading-none uppercase sm:text-[42px]">{title}</h1>
      {description ? <p className="mt-1 max-w-2xl text-base leading-6 text-fg-muted">{description}</p> : null}
    </header>
  );
}
