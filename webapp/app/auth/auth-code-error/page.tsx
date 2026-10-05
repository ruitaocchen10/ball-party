import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = { title: "Sign-in problem", robots: { index: false } };

export default async function AuthCodeErrorPage({
  searchParams,
}: {
  searchParams: Promise<{ reason?: string }>;
}) {
  const { reason } = await searchParams;

  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-sm flex-col justify-center gap-4 px-6">
      <h1 className="font-slab text-3xl leading-none uppercase">
        Sign-in didn&apos;t complete
      </h1>
      <p className="text-sm leading-6 text-fg-muted">
        {reason ?? "The sign-in link expired or was already used."}
      </p>
      <Link
        href="/login"
        className="inline-flex min-h-12 items-center justify-center bg-panel px-4 font-slab text-[15px] tracking-[0.04em] text-panel-fg uppercase transition-colors hover:bg-panel-hover focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel"
      >
        Back to sign in
      </Link>
    </main>
  );
}
