import Link from "next/link";
import { PageShell } from "@/components/foundation/ui-kit/PageShell";

export const metadata = { title: "Terms of Use" };

const LAST_UPDATED = "October 17, 2026";

/** Standalone legal page, public like Privacy and Support: App Review and
 *  signed-out visitors reach it from the sign-in screens without an account. */
export default function TermsPage() {
  return (
    <PageShell variant="prose">
      <p className="text-sm text-fg-muted">Last updated {LAST_UPDATED}</p>
      <h1 className="mt-2 text-3xl font-semibold text-fg">Terms of Use</h1>

      <div className="mt-10 space-y-10 text-[15px] leading-relaxed text-fg">
        <section>
          <p>
            These terms cover your use of Ball Party on the iOS app and at{" "}
            <Link href="/" className="underline underline-offset-2">ballparty.social</Link>. By creating an account or
            using the service you agree to them and to our{" "}
            <Link href="/privacy" className="underline underline-offset-2">Privacy Policy</Link>.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-fg">What you can post</h2>
          <p className="mt-3">
            Ball Party lets you share takes, replies, a display name, a username and a profile photo. You are
            responsible for what you post. There is no tolerance for objectionable content or abusive users. Don&rsquo;t post:
          </p>
          <ul className="mt-3 list-disc space-y-2 pl-5">
            <li>Harassment, bullying, threats or content that encourages violence or self-harm.</li>
            <li>Hate speech, or content that attacks people for who they are.</li>
            <li>Sexually explicit content.</li>
            <li>Spam, scams, or content that impersonates another person.</li>
            <li>Anything illegal, or that infringes someone else&rsquo;s rights.</li>
          </ul>
          <p className="mt-3">
            Disagreeing about football is the point. Attacking people is not.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-fg">Reporting and blocking</h2>
          <p className="mt-3">
            Every take and reply has a Report button, and you can report a player&rsquo;s profile from their profile
            page. A take you report is hidden from you straight away. You can block a player from their profile or your
            Friends list; their takes then disappear for you and yours for them. We review reports and act on them
            promptly.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-fg">What we may do</h2>
          <p className="mt-3">
            We may remove content that breaks these rules and suspend or ban accounts that break them repeatedly or
            seriously, without notice. You can delete your account at any time from Settings.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-fg">The service</h2>
          <p className="mt-3">
            Ball Party is a game and community for football fans. It is free, has no real-money play, and is not
            affiliated with or endorsed by the NFL or any team. We provide it as is, may change or stop parts of it, and
            are not liable for losses from your use of it to the extent the law allows.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-fg">Contact</h2>
          <p className="mt-3">
            Questions or reports we should look at? See{" "}
            <Link href="/support" className="underline underline-offset-2">Support</Link>.
          </p>
        </section>
      </div>
    </PageShell>
  );
}
