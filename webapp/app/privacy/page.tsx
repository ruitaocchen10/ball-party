import Link from "next/link";
import { PageShell } from "@/components/foundation/ui-kit/PageShell";

export const metadata = { title: "Privacy Policy" };

const LAST_UPDATED = "October 19, 2026";

/** Standalone legal page: no Sidebar/DashboardHeader, since App Review and
 *  logged-out visitors both need to reach this without an account. */
export default function PrivacyPage() {
  return (
    <PageShell variant="prose">
      <p className="text-sm text-fg-muted">Last updated {LAST_UPDATED}</p>
      <h1 className="mt-2 text-3xl font-semibold text-fg">Privacy Policy</h1>

      <div className="mt-10 space-y-10 text-[15px] leading-relaxed text-fg">
        <section>
          <p>
            Ball Party (&ldquo;we&rdquo;, &ldquo;us&rdquo;) makes the Ball Party app and{" "}
            <Link href="/" className="underline underline-offset-2">
              ballparty.social
            </Link>
            . This page explains what we collect, why, and the choices you have. It covers both the iOS app and the
            website, since they share one account and one backend.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-fg">Information we collect</h2>
          <ul className="mt-3 list-disc space-y-2 pl-5">
            <li>
              <strong>Account information.</strong> When you sign up we store your email address and a display name.
              If you sign in with Apple or Google, we receive the account identifier those providers give us, and,
              only on your first sign-in, the name they choose to share.
            </li>
            <li>
              <strong>Content you create.</strong> Takes, picks, prompt answers, draft rosters, and other game
              results you post are stored so they can be shown to you and, where the game is a group one, to the
              other players in your lobby or party.
            </li>
            <li>
              <strong>Reports and blocks.</strong> If you report a take or a profile, or block a player, we store
              who reported what and why so we can review it and act on it. The player you report is not told who
              reported them.
            </li>
            <li>
              <strong>Gameplay and party data.</strong> Lobby membership, scores, and game state for the games you
              play, so results and rankings work.
            </li>
            <li>
              <strong>Usage analytics.</strong> Which features you use, such as creating or joining a party,
              starting a game, answering a prompt or sharing an invite link, along with the pages you visit on the
              website and basic device details (app version, device model, operating system). These events are
              linked to your account ID, not to your email or anything you type.
            </li>
          </ul>
          <p className="mt-3">
            We don&rsquo;t collect your location, contacts, photos, camera, or microphone, and we don&rsquo;t work
            out where you are from your IP address. We don&rsquo;t run advertising SDKs, and we don&rsquo;t sell
            your data.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-fg">How we use it</h2>
          <p className="mt-3">We use the information above only to run the product:</p>
          <ul className="mt-3 list-disc space-y-2 pl-5">
            <li>Creating and authenticating your account, and letting you sign in on more than one device.</li>
            <li>Showing your takes, picks, and rankings to you and to the other players in a shared game or lobby.</li>
            <li>Operating core gameplay — scoring, matchmaking within a lobby, and party progress.</li>
            <li>Understanding which features are used and where people get stuck, so we can improve the product
              (usage analytics, in the website and the iOS app).</li>
          </ul>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-fg">Who we share it with</h2>
          <p className="mt-3">
            We use Supabase to host our database, authentication, and file storage, PostHog to process usage
            analytics, and Apple/Google only as sign-in providers you choose to use. We don&rsquo;t share your data with advertisers, data brokers, or
            any other third party, and no data collected in the app is used to track you across other companies&rsquo;
            apps or websites.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-fg">Your choices</h2>
          <ul className="mt-3 list-disc space-y-2 pl-5">
            <li>Edit your display name and profile at any time from Settings.</li>
            <li>
              Turn off usage analytics with the &ldquo;Share usage data&rdquo; switch: in Settings on the website,
              or under Profile &rarr; Privacy in the iOS app. The choice applies to the browser or device you set
              it on.
            </li>
            <li>
              Delete your account from Settings, which removes your display name and profile photo and permanently
              blocks the account from signing in. Your past match results and takes stay on record under
              &ldquo;Deleted player,&rdquo; and the email you signed up with stays on file but can no longer be used
              to sign in. Contact us at the address below if you&rsquo;d like copies of your data first, or have
              questions about what a deletion removes.
            </li>
          </ul>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-fg">Children</h2>
          <p className="mt-3">Ball Party is not directed at children under 13, and we don&rsquo;t knowingly collect information from them.</p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-fg">Changes to this policy</h2>
          <p className="mt-3">
            If this policy changes in a material way, we&rsquo;ll update the date at the top of this page.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-fg">Contact</h2>
          <p className="mt-3">
            Questions about this policy or your data:{" "}
            <a href="mailto:testytesttesty9021@gmail.com" className="underline underline-offset-2">
              testytesttesty9021@gmail.com
            </a>
            . See also our{" "}
            <Link href="/support" className="underline underline-offset-2">
              Support page
            </Link>
            .
          </p>
        </section>
      </div>
    </PageShell>
  );
}
