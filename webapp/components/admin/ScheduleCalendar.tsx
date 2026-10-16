"use client";

import dayGridPlugin from "@fullcalendar/daygrid";
import luxonPlugin from "@fullcalendar/luxon3";
import FullCalendar from "@fullcalendar/react";
import type { EventInput, EventSourceFunc } from "@fullcalendar/core";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";

import { CalendarKey, GameRow, GamesSummary, OpenEcho, PostCard } from "@/components/admin/CalendarCards";
import { ScheduleSlotSummary, slotHref } from "@/components/admin/ScheduleSlotCard";
import {
  easternDate,
  fetchCalendarGames,
  fetchCalendarPosts,
  fetchScheduleRange,
  type CalendarGame,
  type CalendarPost,
  type ScheduleSlot,
} from "@/lib/foundation/content/prompts/schedule";
import { createClient } from "@/lib/supabase/client";

/** What an event on the calendar is; FullCalendar carries it to eventContent. */
type CalendarItem =
  | { kind: "game"; game: CalendarGame }
  | { kind: "games"; games: CalendarGame[] }
  | { kind: "slot"; slot: ScheduleSlot }
  | { kind: "post"; post: CalendarPost }
  | { kind: "echo"; post: CalendarPost };

/** Within a day: games first, then published prompts, opened reminders, ready slots, and planned ones last. */
const RANK = { game: 0, games: 0, post: 1, echo: 2, ready: 3, planned: 4 } as const;

function event(item: CalendarItem, id: string, instant: string, rank: number, url?: string): EventInput {
  return {
    id,
    // A date, not an instant: each item sits on its Eastern day whatever the browser's zone.
    start: easternDate(instant),
    allDay: true,
    // FullCalendar orders a day's events by title, so it carries the rank and then the time.
    title: `${rank}|${instant}`,
    url,
    extendedProps: { item },
  };
}

/**
 * The admin calendar (BPP-15), drawn by FullCalendar: a Monday-to-Sunday week
 * or a month in US Eastern. It shows four kinds of thing, each drawn
 * differently (CalendarCards, and the key above the grid explains them):
 * NFL games, planned prompts (empty, draft, ready) on the day they open, and
 * published prompts (open, locked, resolved, void) on the day they lock, with a
 * slimmer reminder on the day they opened. Published prompts come straight from
 * prompt_posts, so ones composed without a slot appear too. FullCalendar owns
 * the grid and navigation; styling is the `.schedule-calendar` block in globals.css.
 */
export function ScheduleCalendar({ initialDate }: { initialDate: string }) {
  const router = useRouter();
  // Made on first use, in the browser: the page also renders on the server, where a browser client cannot be created.
  const client = useRef<ReturnType<typeof createClient> | null>(null);
  const calendar = useRef<FullCalendar>(null);
  const [showGames, setShowGames] = useState(true);
  const showGamesRef = useRef(true);
  // The view the loaded events were built for: month folds a day's games into one line.
  const loadedViewRef = useRef("dayGridWeek");

  // Games are fetched only while shown, so changing the toggle reloads the events.
  useEffect(() => {
    if (showGamesRef.current === showGames) return;
    showGamesRef.current = showGames;
    calendar.current?.getApi().refetchEvents();
  }, [showGames]);

  const loadEvents: EventSourceFunc = useCallback(
    async (info, success, failure) => {
      try {
        const supabase = (client.current ??= createClient());
        const viewType = calendar.current?.getApi().view.type ?? "dayGridWeek";
        loadedViewRef.current = viewType;
        const monthView = viewType === "dayGridMonth";
        const [slots, posts, games] = await Promise.all([
          fetchScheduleRange(supabase, info.start, info.end),
          fetchCalendarPosts(supabase, info.start, info.end),
          showGamesRef.current ? fetchCalendarGames(supabase, info.start, info.end) : Promise.resolve([] as CalendarGame[]),
        ]);
        const events: EventInput[] = [];

        // A slot that has gone live is its post now, drawn from prompt_posts below.
        for (const slot of slots.filter((candidate) => candidate.state !== "published")) {
          events.push(event({ kind: "slot", slot }, `slot:${slot.id}`, slot.due_at!, slot.state === "ready" ? RANK.ready : RANK.planned, slotHref(slot)));
        }

        const from = info.start.getTime();
        const to = info.end.getTime();
        const within = (instant: string) => new Date(instant).getTime() >= from && new Date(instant).getTime() < to;
        for (const post of posts) {
          const href = `/admin/posts?status=${post.status}`;
          // The full card sits on the day the prompt locks.
          if (within(post.lock_at)) {
            events.push(event({ kind: "post", post }, `post:${post.id}`, post.lock_at, RANK.post, href));
          }
          // And a slim reminder on the day it opened, unless that is the same day.
          if (easternDate(post.created_at) !== easternDate(post.lock_at) && within(post.created_at)) {
            events.push(event({ kind: "echo", post }, `echo:${post.id}`, post.created_at, RANK.echo, href));
          }
        }

        if (monthView) {
          const byDay = new Map<string, CalendarGame[]>();
          for (const game of games) byDay.set(easternDate(game.kickoff), [...(byDay.get(easternDate(game.kickoff)) ?? []), game]);
          for (const [day, dayGames] of byDay) events.push(event({ kind: "games", games: dayGames }, `games:${day}`, dayGames[0].kickoff, RANK.games));
        } else {
          for (const game of games) events.push(event({ kind: "game", game }, `game:${game.id}`, game.kickoff, RANK.game));
        }
        success(events);
      } catch (error) {
        failure(error instanceof Error ? error : new Error("Couldn't load the calendar."));
      }
    },
    [],
  );

  return (
    <div className="flex flex-col gap-4">
      <CalendarKey />
      <button
        type="button"
        role="switch"
        aria-checked={showGames}
        onClick={() => setShowGames((current) => !current)}
        className="flex items-center gap-2 self-start type-label-lg text-fg-muted"
      >
        <span aria-hidden className={`flex h-5 w-9 items-center rounded-full px-0.5 ${showGames ? "bg-fg" : "bg-surface-raised ring-1 ring-line ring-inset"}`}>
          <span className={`h-4 w-4 rounded-full transition-transform ${showGames ? "translate-x-4 bg-surface" : "bg-fg-muted"}`} />
        </span>
        NFL games
      </button>
      <div className="schedule-calendar">
        <FullCalendar
          ref={calendar}
          plugins={[dayGridPlugin, luxonPlugin]}
          timeZone="America/New_York"
          initialView="dayGridWeek"
          initialDate={initialDate}
          firstDay={1}
          fixedWeekCount={false}
          height="auto"
          headerToolbar={{ left: "prev,next today", center: "title", right: "dayGridWeek,dayGridMonth" }}
          buttonText={{ today: "Today", week: "Week", month: "Month" }}
          views={{ dayGridMonth: { dayMaxEvents: 4 } }}
          datesSet={(arg) => {
            // FullCalendar may fetch before it has switched views; rebuild once it has.
            if (arg.view.type !== loadedViewRef.current) calendar.current?.getApi().refetchEvents();
          }}
          eventOrder="title"
          events={loadEvents}
          eventContent={(arg) => {
            const item = arg.event.extendedProps.item as CalendarItem;
            switch (item.kind) {
              case "game":
                return <GameRow game={item.game} />;
              case "games":
                return <GamesSummary games={item.games} />;
              case "slot":
                return <ScheduleSlotSummary slot={item.slot} compact />;
              case "post":
                return <PostCard post={item.post} />;
              case "echo":
                return <OpenEcho post={item.post} />;
            }
          }}
          eventClick={(arg) => {
            if (!arg.event.url) {
              arg.jsEvent.preventDefault();
              return;
            }
            // Stay in the app's router instead of a full page load.
            arg.jsEvent.preventDefault();
            router.push(arg.event.url);
          }}
          eventDisplay="block"
        />
      </div>
    </div>
  );
}
