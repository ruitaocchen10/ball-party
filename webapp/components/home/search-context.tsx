"use client";

import { createContext, useMemo, useState, type ReactNode } from "react";

/**
 * Live state for the Huddle search bar (DashboardHeader's input) and the feed
 * it filters (HuddleFeed), which sit as siblings under Home — a context is
 * the shortest path between them without threading state through Sidebar.
 *
 * `null` outside a provider (DashboardHeader also renders on /party,
 * /settings, /match/[id], /profile, and /solo) — consumers fall back to the
 * plain `<form action="/">` navigation on those routes, since there's no
 * feed there to filter live.
 */
export const SearchQueryContext = createContext<{ query: string; setQuery: (value: string) => void } | null>(null);

/** `initialQuery` seeds from the URL's `?q=`, so a shared search link renders the same filtered feed before any hydration. */
export function SearchQueryProvider({ initialQuery, children }: { initialQuery: string; children: ReactNode }) {
  const [query, setQuery] = useState(initialQuery);
  const value = useMemo(() => ({ query, setQuery }), [query]);
  return <SearchQueryContext.Provider value={value}>{children}</SearchQueryContext.Provider>;
}
