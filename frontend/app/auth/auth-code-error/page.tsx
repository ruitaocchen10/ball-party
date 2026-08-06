import Link from "next/link";

export default async function AuthCodeErrorPage({
  searchParams,
}: {
  searchParams: Promise<{ reason?: string }>;
}) {
  const { reason } = await searchParams;

  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-sm flex-col justify-center gap-4 px-6">
      <h1 className="text-2xl font-semibold tracking-tight">Sign-in didn&apos;t complete</h1>
      <p className="text-sm leading-6 text-black/60 dark:text-white/60">
        {reason ?? "The sign-in link expired or was already used."}
      </p>
      <Link
        href="/login"
        className="inline-flex h-11 items-center justify-center rounded-lg bg-foreground px-4 text-sm font-medium text-background"
      >
        Back to sign in
      </Link>
    </main>
  );
}
