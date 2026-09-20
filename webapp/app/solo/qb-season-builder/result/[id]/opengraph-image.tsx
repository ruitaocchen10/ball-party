import { notFound } from "next/navigation";
import { ImageResponse } from "next/og";

import { fetchResult } from "@/lib/games/qb-season-builder/read";
import { shareCardFromResult } from "@/lib/games/qb-season-builder/share-card";
import { createClient } from "@/lib/supabase/server";

export const alt = "A QB Season Builder season";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

const SURFACE = "#111311";
const CREAM = "#f4efe4";
const FG = "#e8e3d6";
const MUTED = "#8f8b7f";
const LINE = "rgba(232, 227, 214, 0.22)";

/** The public link-preview card for one completed season. */
export default async function Image({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const result = await fetchResult(await createClient(), id);
  if (!result) notFound();
  const card = shareCardFromResult(result);

  return new ImageResponse(
    (
      <div style={{ width: "100%", height: "100%", display: "flex", flexDirection: "column", background: SURFACE, color: FG, padding: 64 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div style={{ display: "flex", fontSize: 40, fontWeight: 700, letterSpacing: 3, color: CREAM }}>QB SEASON BUILDER</div>
          <div style={{ display: "flex", fontSize: 30, letterSpacing: 2, color: MUTED }}>SOLO CHALLENGE</div>
        </div>

        <div style={{ display: "flex", flexDirection: "column", marginTop: 52 }}>
          <div style={{ display: "flex", fontSize: 84, fontWeight: 700, color: CREAM }}>{card.title.toUpperCase()}</div>
          <div style={{ display: "flex", marginTop: 12, fontSize: 38, letterSpacing: 2, color: FG }}>{card.statLine}</div>
        </div>

        <div style={{ display: "flex", marginTop: 42, borderTop: `2px solid ${LINE}`, borderBottom: `2px solid ${LINE}`, padding: "26px 0", justifyContent: "space-between", alignItems: "center" }}>
          <div style={{ display: "flex", flexDirection: "column" }}>
            <div style={{ display: "flex", fontSize: 20, letterSpacing: 2, color: MUTED }}>RECORD</div>
            <div style={{ display: "flex", marginTop: 6, fontSize: 50, fontWeight: 700, color: CREAM }}>{card.record}</div>
          </div>
          <div style={{ display: "flex", flexDirection: "column", maxWidth: 480 }}>
            <div style={{ display: "flex", fontSize: 20, letterSpacing: 2, color: MUTED }}>PLAYOFFS</div>
            <div style={{ display: "flex", marginTop: 10, fontSize: 30, color: CREAM }}>{card.playoffs.toUpperCase()}</div>
          </div>
          <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end" }}>
            <div style={{ display: "flex", fontSize: 20, letterSpacing: 2, color: MUTED }}>SCORE</div>
            <div style={{ display: "flex", marginTop: 2, fontSize: 68, fontWeight: 700, color: CREAM }}>{card.score}</div>
          </div>
        </div>

        <div style={{ display: "flex", marginTop: "auto", alignItems: "center", gap: 16 }}>
          <div style={{ display: "flex", fontSize: 20, letterSpacing: 2, color: MUTED }}>AWARDS</div>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 10 }}>
            {card.awards.length ? card.awards.map((award) => (
              <div key={award} style={{ display: "flex", border: `1px solid ${LINE}`, padding: "7px 12px", fontSize: 23, color: CREAM }}>{award.toUpperCase()}</div>
            )) : <div style={{ display: "flex", fontSize: 23, color: FG }}>NONE</div>}
          </div>
        </div>
      </div>
    ),
    { ...size },
  );
}
