import Link from "next/link";

import { ProfileEditor } from "@/components/foundation/identity/ProfileEditor";
import { ProfileAvatar } from "@/components/foundation/identity/ProfileAvatar";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { canViewProfile, isSignedInViewer } from "@/lib/foundation/identity/viewer";
import { GuestUpgrade } from "@/components/foundation/identity/GuestUpgrade";
import { matchGameName } from "@/lib/platform/orchestration/catalog";
import { completedMatchesFromHistory, recentMatches, summarizeMultiplayerProfile, type CompletedMatch, type CompletedMatchWithMode } from "@/lib/foundation/identity/summary";
import { createClient } from "@/lib/supabase/server";

/** A player's durable record, kept deliberately separate from a live room. */
export default async function ProfilePage() {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  if (!isSignedInViewer(claims)) return <SignedOutProfile />;
  if (!canViewProfile(claims)) return <GuestProfile />;

  const [{ data: profile }, { data: historyRows }] = await Promise.all([
    supabase
      .from("profiles")
      .select("display_name, avatar_url, created_at")
      .eq("id", claims.sub)
      .single(),
    supabase.rpc("my_match_history"),
  ]);

  const matches = completedMatchesFromHistory(historyRows ?? []);
  const multiplayerSummary = summarizeMultiplayerProfile(matches);
  const recentMultiplayer = recentMatches(matches.filter((match) => match.mode !== "solo"));
  const recentSolo = recentMatches(matches.filter((match) => match.mode === "solo"));
  const displayName = profile?.display_name ?? (claims.email as string | undefined) ?? "Player";
  const email = (claims.email as string | undefined) ?? null;
  const avatarUrl = profile?.avatar_url ?? null;

  return (
    <>
      <Sidebar displayName={displayName} email={email} avatarUrl={avatarUrl} canPlaySolo />
      <main className="mx-auto w-full max-w-7xl flex-1 px-4 pt-10 pb-16 sm:px-6 sm:pt-12 lg:px-8 lg:pt-14 lg:pb-20">
        <header className="flex flex-col gap-5 border-b border-line pb-7 sm:flex-row sm:items-end">
          <ProfileAvatar name={displayName} avatarUrl={profile?.avatar_url ?? null} />
          <div className="min-w-0 flex-1">
            <p className="mb-2 font-mono text-[10px] tracking-[0.15em] text-hidden-text uppercase">
              Player profile
            </p>
            <h1 className="font-slab text-[36px] leading-[.94] uppercase sm:text-[46px]">
              {displayName}
            </h1>
            <p className="mt-2 text-sm text-fg-muted">
              Playing since {joinedMonth(profile?.created_at)}
            </p>
          </div>
          <ProfileEditor
            displayName={displayName}
            avatarUrl={profile?.avatar_url ?? null}
            userId={claims.sub}
          />
        </header>

        <section aria-label="Career stats" className="grid grid-cols-2 gap-2.5 py-6 sm:grid-cols-4 sm:gap-3">
          <Stat value="" label="Games played" />
          <Stat value={multiplayerSummary.wins} label="Multiplayer wins" />
          <Stat value={`${multiplayerSummary.winRate}%`} label="Multiplayer win rate" />
          <Stat value="" label="Best streak" />
        </section>

        <div className="grid gap-7 border-t border-line pt-7 lg:grid-cols-[minmax(0,1.7fr)_minmax(250px,1fr)] lg:gap-9">
          <section aria-labelledby="recent-games-heading">
            <SectionHeading id="recent-games-heading">Recent results</SectionHeading>
            {recentMultiplayer.length || recentSolo.length ? (
              <div className="mt-3 grid gap-6">
                {recentMultiplayer.length ? <RecentResults title="Multiplayer" matches={recentMultiplayer} multiplayer /> : null}
                {recentSolo.length ? <RecentResults title="Solo" matches={recentSolo} multiplayer={false} /> : null}
              </div>
            ) : (
              <EmptyRecord />
            )}
          </section>

          <aside className="self-start rounded-card bg-panel p-5 text-panel-fg shadow-card sm:p-6">
            <p className="font-mono text-[10px] tracking-[0.15em] text-panel-muted uppercase">Your next game</p>
            <h2 className="mt-2 font-slab text-[25px] leading-[.98] uppercase">
              Make the record
            </h2>
            <p className="mt-3 max-w-[32ch] text-sm leading-6 text-panel-muted">
              Every completed game lands here — play with friends, chase a streak, and leave a mark.
            </p>
            <Link
              href="/"
              className="mt-5 inline-flex bg-hidden px-3.5 py-3 font-mono text-[10px] font-bold tracking-[0.13em] text-white uppercase transition-colors hover:bg-hidden-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel-fg"
            >
              Find a game
            </Link>
          </aside>
        </div>
      </main>
    </>
  );
}

function GuestProfile() {
  return (
    <>
      {/* A guest has a real session for playing, just not an account — the
          same floor playSolo itself checks — so the Solo games links work here. */}
      <Sidebar canPlaySolo />
      <main className="mx-auto flex w-full max-w-7xl flex-1 px-4 py-10 sm:px-6 sm:py-12 lg:px-8 lg:py-14">
        <section className="max-w-xl">
          <p className="font-mono text-[10px] tracking-[0.15em] text-hidden-text uppercase">Guest game</p>
          <h1 className="mt-3 font-slab text-[36px] leading-[.96] uppercase sm:text-[46px]">Make your record yours</h1>
          <p className="mt-4 text-[15px] leading-6 text-fg-muted">Guest names are just for the current game. Create an account to save a profile and keep your results.</p>
          <div className="mt-6"><GuestUpgrade /></div>
        </section>
      </main>
    </>
  );
}

function SignedOutProfile() {
  return (
    <>
      <Sidebar />
      <main className="mx-auto flex w-full max-w-7xl flex-1 px-4 py-10 sm:px-6 sm:py-12 lg:px-8 lg:py-14">
        <section className="max-w-xl">
          <p className="font-mono text-[10px] tracking-[0.15em] text-hidden-text uppercase">Player profile</p>
          <h1 className="mt-3 font-slab text-[36px] leading-[.96] uppercase sm:text-[46px]">Your record starts here</h1>
          <p className="mt-4 text-[15px] leading-6 text-fg-muted">Sign in to keep a record of your games, wins, and streaks.</p>
          <Link href="/login?next=/profile" className="mt-6 inline-flex bg-panel px-4 py-3 font-mono text-[10px] font-bold tracking-[0.13em] text-panel-fg uppercase focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel">Sign in</Link>
        </section>
      </main>
    </>
  );
}

function Stat({ value, label }: { value: string | number; label: string }) {
  return <div className="rounded-card bg-panel-shade px-4 py-4 text-panel-fg"><strong className="block font-slab text-[28px] leading-none">{value}</strong><span className="mt-1.5 block font-mono text-[9px] tracking-[0.12em] text-panel-muted uppercase">{label}</span></div>;
}

function SectionHeading({ id, children }: { id: string; children: React.ReactNode }) {
  return <h2 id={id} className="font-mono text-[10px] font-bold tracking-[0.15em] text-fg-muted uppercase">{children}</h2>;
}

function RecentResults({ title, matches, multiplayer }: { title: string; matches: CompletedMatchWithMode[]; multiplayer: boolean }) {
  return (
    <section aria-label={`${title} results`}>
      <h3 className="font-mono text-[9px] font-bold tracking-[0.13em] text-fg-muted uppercase">{title}</h3>
      <ol className="mt-2.5 grid gap-2.5">
        {matches.map((match) => <RecentGame key={match.id} match={match} multiplayer={multiplayer} />)}
      </ol>
    </section>
  );
}

function RecentGame({ match, multiplayer }: { match: CompletedMatch; multiplayer: boolean }) {
  const score = match.rawScore === null ? null : Number.isInteger(match.rawScore) ? String(match.rawScore) : match.rawScore.toFixed(1);
  return <li className="grid grid-cols-[5px_minmax(0,1fr)_auto] gap-x-4 bg-panel py-4 pr-4 text-panel-fg shadow-card"><span className="bg-hidden" /><div><h3 className="font-slab text-xl leading-none uppercase">{matchGameName(match.game)}</h3><p className="mt-1.5 text-sm text-panel-muted"><time dateTime={match.endedAt}>{shortDate(match.endedAt)}</time>{score === null ? "" : ` · Score ${score}`}</p></div><div className="self-center text-right">{multiplayer ? <><strong className="block font-slab text-2xl leading-none">{formatPlacement(match.placement)}</strong><span className="font-mono text-[9px] tracking-[0.1em] text-hidden-ink uppercase">{match.placement === 1 ? "Win" : "Finish"}</span></> : <span className="font-mono text-[9px] tracking-[0.1em] text-panel-muted uppercase">Solo</span>}</div></li>;
}

function EmptyRecord() {
  return <div className="mt-3 rounded-card bg-surface-raised px-5 py-6 text-sm leading-6 text-fg-muted shadow-well">No completed games yet. Your first result will show up here after the final score is in.</div>;
}

function joinedMonth(date?: string) { return date ? new Intl.DateTimeFormat("en", { month: "long", year: "numeric" }).format(new Date(date)) : "today"; }
function shortDate(date: string) { return new Intl.DateTimeFormat("en", { month: "short", day: "numeric", year: "numeric" }).format(new Date(date)); }
function formatPlacement(value: number | null) { return value === 1 ? "1st" : value === 2 ? "2nd" : value === 3 ? "3rd" : value ? `${value}th` : "—"; }
