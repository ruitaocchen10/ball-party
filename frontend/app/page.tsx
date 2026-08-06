import { redirect } from "next/navigation";

import { Button } from "@/components/ui/Button";
import { signOut } from "@/lib/auth/actions";
import { createLobby, goToLobby } from "@/lib/lobbies/actions";
import { createClient } from "@/lib/supabase/server";

export default async function Home(props: PageProps<"/">) {
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

  const { error } = await props.searchParams;
  const errorText = Array.isArray(error) ? error[0] : error;

  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-md flex-col justify-center gap-7 px-6 py-16">
      <header className="flex flex-col gap-2">
        <h1 className="font-slab text-4xl leading-none -skew-x-7 uppercase">Ball Party</h1>
        <p className="font-mono text-[10px] tracking-[0.15em] text-fg-muted uppercase">
          Dealt in as {profile?.display_name ?? claims.email}
        </p>
      </header>

      {errorText ? (
        <p
          role="alert"
          className="rounded border border-hidden/40 bg-hidden/10 px-3.5 py-2.5 text-sm text-hidden-text"
        >
          {errorText}
        </p>
      ) : null}

      <form action={createLobby}>
        <Button type="submit">Deal a new table</Button>
      </form>

      <div className="flex items-center gap-3 font-mono text-[10px] tracking-[0.15em] text-fg-muted uppercase">
        <span className="h-px flex-1 bg-line" />
        or
        <span className="h-px flex-1 bg-line" />
      </div>

      <form action={goToLobby} className="flex flex-col gap-3">
        <label
          htmlFor="code"
          className="font-mono text-[10px] tracking-[0.15em] text-fg-muted uppercase"
        >
          Join with a code
        </label>
        <div className="flex gap-2">
          {/* The join code is the loudest thing on this screen because for ten
              seconds it's the only thing anyone needs. */}
          <input
            id="code"
            name="code"
            required
            maxLength={5}
            autoCapitalize="characters"
            autoComplete="off"
            spellCheck={false}
            placeholder="K7M2Q"
            className="h-12 min-w-0 flex-1 rounded border border-line bg-table-raised px-3.5 font-mono text-lg tracking-[0.28em] text-fg uppercase outline-none placeholder:text-fg-muted focus:border-stock"
          />
          <Button type="submit" variant="ghost" fullWidth={false}>
            Join
          </Button>
        </div>
      </form>

      <form action={signOut} className="mt-2">
        <button
          type="submit"
          className="cursor-pointer text-sm text-fg-muted underline decoration-line underline-offset-4 transition-colors hover:text-fg hover:decoration-fg"
        >
          Sign out
        </button>
      </form>
    </main>
  );
}
