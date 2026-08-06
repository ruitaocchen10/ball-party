import Link from "next/link";

export default async function AuthCodeErrorPage({
  searchParams,
}: {
  searchParams: Promise<{ reason?: string }>;
}) {
  const { reason } = await searchParams;

  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-sm flex-col justify-center gap-4 px-6">
      <h1 className="font-slab text-3xl leading-none -skew-x-7 uppercase">
        Sign-in didn&apos;t complete
      </h1>
      <p className="text-sm leading-6 text-fg-muted">
        {reason ?? "The sign-in link expired or was already used."}
      </p>
      <Link
        href="/login"
        className="inline-flex min-h-12 items-center justify-center rounded bg-stock px-4 font-slab text-[15px] tracking-[0.04em] -skew-x-7 text-ink uppercase transition-colors hover:bg-[#fffdf7] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stock"
      >
        Back to sign in
      </Link>
    </main>
  );
}
