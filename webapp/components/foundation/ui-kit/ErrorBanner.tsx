/**
 * The banner a page shows when it redirected back to itself with `?error=`
 * — see `withError` in lib/lobbies/actions.ts. Pulled out once a fourth page
 * (Home, Party, Solo, Social) needed the exact same markup.
 */
export function ErrorBanner({ children }: { children: React.ReactNode }) {
  return (
    <p
      role="alert"
      className="mt-6 border border-hidden/40 bg-hidden/10 px-3.5 py-2.5 text-sm text-hidden-text"
    >
      {children}
    </p>
  );
}
