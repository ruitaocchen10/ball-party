import { redirect } from "next/navigation";

/** Legacy route retained only so saved links reach the canonical Home feed. */
export default async function SocialPage(props: PageProps<"/social">) {
  const { q } = await props.searchParams;
  redirect(typeof q === "string" && q ? `/?q=${encodeURIComponent(q)}` : "/");
}
