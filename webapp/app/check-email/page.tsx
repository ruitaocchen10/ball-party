import Link from "next/link";

export default function CheckEmailPage() {
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-sm flex-col justify-center gap-4 px-6">
      <h1 className="font-slab text-3xl leading-none uppercase">Check your email</h1>
      <p className="text-sm leading-6 text-fg-muted">
        We sent you a confirmation link. Open it to finish creating your account —
        you won&apos;t be able to join a game until you do.
      </p>
      <Link
        href="/login"
        className="text-sm font-medium text-fg underline decoration-line underline-offset-4 transition-colors hover:decoration-fg"
      >
        Back to sign in
      </Link>
    </main>
  );
}
