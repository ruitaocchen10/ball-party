import Link from "next/link";

export const metadata = { title: "Support" };

/** Standalone support page: the URL App Store Connect points to for both
 *  "App Support URL" and, doubling up, general contact. No account needed
 *  to reach it. */
export default function SupportPage() {
  return (
    <main className="mx-auto w-full max-w-2xl px-6 py-16 text-fg">
      <h1 className="text-3xl font-semibold text-panel">Support</h1>

      <div className="mt-10 space-y-10 text-[15px] leading-relaxed text-fg">
        <section>
          <p>
            Running into a bug, have a question about how a game works, or want to request a feature? Email us and
            we&rsquo;ll get back to you.
          </p>
          <p className="mt-4">
            <a href="mailto:testytesttesty9021@gmail.com" className="underline underline-offset-2 text-panel">
              testytesttesty9021@gmail.com
            </a>
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-panel">Common questions</h2>
          <div className="mt-4 space-y-6">
            <div>
              <h3 className="font-medium text-panel">How do I delete my account?</h3>
              <p className="mt-1 text-fg-muted">
                Open Settings in the app, then use Delete Account. If you&rsquo;d rather we do it for you, email us
                from the address on your account and we&rsquo;ll confirm and remove it.
              </p>
            </div>
            <div>
              <h3 className="font-medium text-panel">I can&rsquo;t sign in.</h3>
              <p className="mt-1 text-fg-muted">
                Try the same sign-in method you used originally (Apple, Google, or email) — accounts aren&rsquo;t
                automatically linked across methods. Still stuck? Email us with the address you signed up with.
              </p>
            </div>
            <div>
              <h3 className="font-medium text-panel">How do I join a friend&rsquo;s party or lobby?</h3>
              <p className="mt-1 text-fg-muted">Ask them for the lobby code from their Party tab and enter it from yours.</p>
            </div>
          </div>
        </section>

        <section>
          <p className="text-fg-muted">
            See also our{" "}
            <Link href="/privacy" className="underline underline-offset-2">
              Privacy Policy
            </Link>
            .
          </p>
        </section>
      </div>
    </main>
  );
}
