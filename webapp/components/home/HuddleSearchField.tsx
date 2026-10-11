"use client";

import { Search } from "lucide-react";
import { useContext } from "react";

import { SearchQueryContext } from "@/components/home/search-context";

/**
 * The search bar itself. Inside a SearchQueryProvider (Home only), typing
 * filters HuddleFeed live and Enter is a no-op; everywhere else DashboardHeader
 * renders this, it's a plain GET to "/" so the query still lands on Home.
 */
export function HuddleSearchField() {
  const search = useContext(SearchQueryContext);

  return (
    <form
      action="/"
      role="search"
      className="mx-auto w-full max-w-xl"
      onSubmit={(event) => {
        if (search) event.preventDefault();
      }}
    >
      <label className="sr-only" htmlFor="dashboard-search">
        Search social posts
      </label>
      <div className="flex h-10 items-center gap-2.5 rounded-card bg-surface-raised px-3 ring-1 ring-line ring-inset transition-colors focus-within:ring-fg-muted">
        <Search aria-hidden className="h-4 w-4 shrink-0 text-fg-muted" strokeWidth={1.8} />
        <input
          id="dashboard-search"
          name="q"
          type="search"
          placeholder="Search social posts"
          defaultValue={search?.query}
          onChange={search ? (event) => search.setQuery(event.target.value) : undefined}
          className="min-w-0 flex-1 bg-transparent font-mono text-xs tracking-[0.02em] text-fg outline-none placeholder:text-fg-muted"
        />
        {search ? null : <kbd className="hidden rounded-chip border border-line px-1.5 py-0.5 font-mono text-[9px] text-fg-muted lg:block">↵</kbd>}
      </div>
    </form>
  );
}
