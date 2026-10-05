import type { Metadata } from "next";
import Link from "next/link";
import { PageShell } from "@/components/foundation/ui-kit/PageShell";

export const metadata: Metadata = { title: "Check your email", robots: { index: false } };

export default function CheckEmailPage() {
  return (
    <PageShell variant="form">
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
    </PageShell>
  );
}
