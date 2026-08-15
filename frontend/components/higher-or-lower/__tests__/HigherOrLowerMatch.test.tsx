import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { HigherOrLowerMatch } from "@/components/higher-or-lower/HigherOrLowerMatch";
import type { Board, Card, Player } from "@/lib/higher-or-lower/board";

/**
 * The match screen, at the slice where a ladder exists and nothing can be
 * called yet.
 *
 * jsdom on purpose: everything asserted here is behaviour the component
 * decides — which two cards the table is looking at, which number is on screen
 * and which is withheld. Whether the concealed weave is actually red, and
 * whether the two cards sit side by side at this width, are questions only a
 * CSS engine can answer and are out of reach here rather than faked with a
 * class assertion.
 *
 * The withholding is asserted twice over, because a screen is the weakest half
 * of it: the number is absent from the DOM, not merely styled out of the way.
 * The server-side half — that the row never carried the number at all — is
 * supabase/tests/0032_higher_or_lower_board.test.sql.
 */

const MATCH = "11111111-1111-1111-1111-111111111111";

function card(over: Partial<Card> = {}): Card {
  return {
    match_id: MATCH,
    ordinal: 0,
    player_id: "00-0000001",
    display_name: "Saquon Barkley",
    position: "RB",
    season: 2018,
    team: "NYG",
    week: null,
    opponent: null,
    headshot_url: "https://static.www.nfl.com/image/private/f_auto,q_auto/league/abc",
    points: null,
    revealed_at: null,
    ...over,
  };
}

/** The anchor face up, then three challengers with their points withheld. */
function ladder(): Card[] {
  return [
    card({ ordinal: 0, display_name: "Saquon Barkley", points: 289.4, revealed_at: "2026-08-15T12:00:00Z" }),
    card({ ordinal: 1, display_name: "Patrick Mahomes", position: "QB", season: 2019, team: "KC" }),
    card({ ordinal: 2, display_name: "Justin Jefferson", position: "WR", season: 2022, team: "MIN" }),
    card({ ordinal: 3, display_name: "Travis Kelce", position: "TE", season: 2020, team: "KC" }),
  ];
}

const BOARD: Board = {
  questionCount: 12,
  currentQuestion: 1,
  scoringMode: "season_total",
  seasonFrom: 2010,
  seasonTo: 2025,
};

const PLAYERS: Player[] = [
  { match_id: MATCH, user_id: "u0", seat: 0, display_name: "Ava" },
  { match_id: MATCH, user_id: "u1", seat: 1, display_name: "Ben" },
];

function renderMatch(over: { board?: Partial<Board>; cards?: Card[]; players?: Player[] } = {}) {
  return render(
    <HigherOrLowerMatch
      viewerId="u0"
      initial={{
        board: { ...BOARD, ...over.board },
        cards: over.cards ?? ladder(),
        players: over.players ?? PLAYERS,
      }}
    />,
  );
}

describe("HigherOrLowerMatch", () => {
  it("shows the anchor with its points and the challenger with them withheld", () => {
    renderMatch();

    const anchor = screen.getByRole("group", { name: /anchor/i });
    expect(anchor).toHaveTextContent("Saquon Barkley");
    expect(anchor).toHaveTextContent("289.4");

    const challenger = screen.getByRole("group", { name: /challenger/i });
    expect(challenger).toHaveTextContent("Patrick Mahomes");
    expect(challenger).toHaveTextContent("? ? ?");
    expect(challenger).not.toHaveTextContent("289.4");
  });

  // The concealed panel's face is out of the accessibility tree, the way the
  // auction's is, so the status region is the whole announcement rather than
  // one of two competing ones.
  it("announces the pair, including which number is being withheld", () => {
    renderMatch();

    expect(screen.getByRole("status")).toHaveTextContent(
      "Question 1 of 12. Saquon Barkley scored 289.4 fantasy points. Patrick Mahomes is hidden.",
    );
  });

  it("names the question and how many there are", () => {
    renderMatch();

    expect(screen.getByText("Question 1 of 12")).toBeInTheDocument();
  });

  it("gives each card the cues a call is made from", () => {
    renderMatch();

    expect(screen.getByRole("group", { name: /anchor/i })).toHaveTextContent("RB · 2018 · NYG");
    expect(screen.getByRole("group", { name: /challenger/i })).toHaveTextContent("QB · 2019 · KC");
  });

  // The row's week and opponent are nullable — null for a whole season, set for
  // one game — so both shapes are rendered here. Only season mode deals today;
  // weekly boards are #29.
  it("names the week and the opponent on a card that has them", () => {
    renderMatch({
      cards: [
        card({ ordinal: 0, points: 24.6, revealed_at: "2026-08-15T12:00:00Z", week: 12, opponent: "CHI" }),
        card({ ordinal: 1, display_name: "Patrick Mahomes", position: "QB", season: 2019, team: "KC", week: 4, opponent: "DET" }),
      ],
      board: { scoringMode: "weekly" },
    });

    expect(screen.getByRole("group", { name: /anchor/i })).toHaveTextContent(
      "RB · 2018 · Week 12 · NYG vs. CHI",
    );
    expect(screen.getByRole("group", { name: /challenger/i })).toHaveTextContent(
      "QB · 2019 · Week 4 · KC vs. DET",
    );
  });

  // The ladder climbs: every card is a challenger once and the anchor after
  // that, so the pair the table is looking at is the current question and the
  // card before it rather than two fixed rows.
  it("moves both cards along as the question advances", () => {
    renderMatch({
      board: { currentQuestion: 3 },
      cards: [
        card({ ordinal: 0, display_name: "Saquon Barkley", points: 289.4, revealed_at: "2026-08-15T12:00:00Z" }),
        card({ ordinal: 1, display_name: "Patrick Mahomes", points: 417.1, revealed_at: "2026-08-15T12:01:00Z" }),
        card({ ordinal: 2, display_name: "Justin Jefferson", points: 368.2, revealed_at: "2026-08-15T12:02:00Z" }),
        card({ ordinal: 3, display_name: "Travis Kelce" }),
      ],
    });

    expect(screen.getByRole("group", { name: /anchor/i })).toHaveTextContent("Justin Jefferson");
    expect(screen.getByRole("group", { name: /anchor/i })).toHaveTextContent("368.2");
    expect(screen.getByRole("group", { name: /challenger/i })).toHaveTextContent("Travis Kelce");
    expect(screen.queryByText("417.1")).not.toBeInTheDocument();
    expect(screen.getByText("Question 3 of 12")).toBeInTheDocument();
  });

  it("says who is at the table and what the board was dealt from", () => {
    renderMatch();

    expect(screen.getByText("Ava")).toBeInTheDocument();
    expect(screen.getByText("Ben")).toBeInTheDocument();
    expect(screen.getByRole("note", { name: /format/i })).toHaveTextContent("season total · 2010-2025");
  });

  // A card the server has not sent yet is a normal state, not a crash: the
  // screen renders through it rather than blanking.
  it("waits rather than breaking when the next card has not arrived", () => {
    renderMatch({ board: { currentQuestion: 9 } });

    expect(screen.getByText(/waiting for the next card/i)).toBeInTheDocument();
  });
});
