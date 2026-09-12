import { redirect } from "next/navigation";

/** Keep the former placeholder URL usable after Posts replaced Live. */
export default function AdminLivePage() {
  redirect("/admin/posts");
}
