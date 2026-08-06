import Link from "next/link";

export default function CheckEmailPage() {
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-sm flex-col justify-center gap-4 px-6">
      <h1 className="text-2xl font-semibold tracking-tight">Check your email</h1>
      <p className="text-sm leading-6 text-black/60 dark:text-white/60">
        We sent you a confirmation link. Open it to finish creating your account —
        you won&apos;t be able to join a game until you do.
      </p>
      <Link
        href="/login"
        className="text-sm font-medium underline underline-offset-4 decoration-black/30 dark:decoration-white/30"
      >
        Back to sign in
      </Link>
    </main>
  );
}
