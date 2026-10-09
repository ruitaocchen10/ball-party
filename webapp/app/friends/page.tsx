import { redirect } from "next/navigation";

/** Friends moved into the Profile page; this keeps old links and bookmarks working. */
export default function FriendsPage() {
  redirect("/profile?tab=friends");
}
