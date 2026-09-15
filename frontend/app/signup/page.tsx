import { AuthForm } from "@/components/foundation/identity/AuthForm";
import { safeNextPath } from "@/lib/foundation/identity/next";

export const metadata = { title: "Create an account · Ball Party" };

export default async function SignupPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const { next } = await searchParams;
  const safeNext = safeNextPath(next);

  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-sm flex-col justify-center px-6 py-16">
      <AuthForm mode="signup" next={safeNext} />
    </main>
  );
}
