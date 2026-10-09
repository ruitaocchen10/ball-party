import { AuthForm } from "@/components/foundation/identity/AuthForm";
import { safeNextPath } from "@/lib/foundation/identity/next";
import { PageShell } from "@/components/foundation/ui-kit/PageShell";

export const metadata = { title: "Sign in", robots: { index: false } };

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const { next } = await searchParams;
  const safeNext = safeNextPath(next);

  return (
    <PageShell variant="form">
      <AuthForm mode="login" next={safeNext} />
    </PageShell>
  );
}
