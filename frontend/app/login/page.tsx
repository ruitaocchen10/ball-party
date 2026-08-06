import { AuthForm } from "@/components/auth/AuthForm";

export const metadata = { title: "Sign in · Ball Party" };

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const { next } = await searchParams;
  const safeNext = next?.startsWith("/") && !next.startsWith("//") ? next : "/";

  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-sm flex-col justify-center px-6 py-16">
      <AuthForm mode="login" next={safeNext} />
    </main>
  );
}
