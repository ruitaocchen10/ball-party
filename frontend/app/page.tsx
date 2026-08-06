import { redirect } from "next/navigation";

import { signOut } from "@/lib/auth/actions";
import { createClient } from "@/lib/supabase/server";

export default async function Home() {
  const supabase = await createClient();

  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;
  // proxy.ts already guards this route; this is the belt to its braces, and it
  // narrows the type so `sub` can be used below.
  if (!claims) redirect("/login");

  const { data: profile } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", claims.sub)
    .single();

  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-md flex-col justify-center gap-8 px-6 py-16">
      <header className="flex flex-col gap-1.5">
        <h1 className="text-3xl font-semibold tracking-tight">Ball Party</h1>
        <p className="text-sm text-black/55 dark:text-white/55">
          Signed in as {profile?.display_name ?? claims.email}
        </p>
      </header>

      <p className="text-sm leading-6 text-black/70 dark:text-white/70">
        Rooms aren&apos;t wired up yet. Create and join land here next.
      </p>

      <form action={signOut}>
        <button
          type="submit"
          className="h-11 rounded-lg border border-black/15 px-4 text-sm font-medium transition-colors hover:bg-black/[.04] dark:border-white/20 dark:hover:bg-white/[.06]"
        >
          Sign out
        </button>
      </form>
    </main>
  );
}
