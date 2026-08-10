"""Tests for the sampler's board composition.

The sampler is a diagnostic — it deals boards so tier bands can be tuned by
reading names. It is not the real dealer; lot scheduling belongs to the auction,
in `private.deal_auction_board`.

But the two have to agree on composition, or the mix that was tuned here is not
the mix that gets dealt at the table. These assertions are deliberately the same
numbers as the composition tests in
supabase/tests/0010_auction_board.test.sql. If one side drifts from the game
doc, exactly one of the two suites goes red.

Run with: python3 -m unittest discover scripts/player_pool
"""

import random
import unittest
from decimal import Decimal
from collections import Counter

from build_pool import deal_sample_board
from transform import PlayerWeek


def pool(position, tier, n):
    """n interchangeable player-weeks in one (position, tier) cell."""
    return [
        PlayerWeek(
            player_id=f"{position}-{tier}-{i:04d}",
            display_name=f"{position} {tier} {i}",
            position=position,
            season=2015,
            week=1 + (i % 17),
            team="NYG",
            opponent="DAL",
            points=Decimal("10.0"),
            pos_rank=1 + i,
            tier=tier,
        )
        for i in range(n)
    ]


def full_pool():
    rows = []
    for position in ("QB", "RB", "WR", "TE"):
        for tier in ("star", "solid", "deep"):
            rows += pool(position, tier, 40)
    return rows


class TestSampleBoard(unittest.TestCase):
    def setUp(self):
        self.rows = full_pool()

    def board(self, seed=1):
        return deal_sample_board(self.rows, random.Random(seed))

    def test_a_board_is_twenty_lots(self):
        self.assertEqual(len(self.board()), 20)

    def test_the_base_lots_are_four_of_each_position(self):
        # 16 base + 4 flex, and the flex lots can only add to RB, WR and TE, so
        # the check that survives the sampler not marking flex is the floor.
        counts = Counter(lot.position for lot in self.board())
        self.assertEqual(counts["QB"], 4)
        for position in ("RB", "WR", "TE"):
            self.assertGreaterEqual(counts[position], 4)

    def test_the_flex_lots_only_ever_add_to_rb_wr_te(self):
        counts = Counter(lot.position for lot in self.board())
        self.assertEqual(sum(counts[p] - 4 for p in ("RB", "WR", "TE")), 4)

    def test_the_tier_quota_is_seven_eight_five(self):
        counts = Counter(lot.tier for lot in self.board())
        self.assertEqual(counts["star"], 7)
        self.assertEqual(counts["solid"], 8)
        self.assertEqual(counts["deep"], 5)

    def test_no_player_season_appears_twice_on_a_board(self):
        board = self.board()
        seen = {(lot.player_id, lot.season) for lot in board}
        self.assertEqual(len(seen), len(board))

    def test_the_same_seed_deals_the_same_board(self):
        self.assertEqual(
            [lot.player_id for lot in self.board(seed=7)],
            [lot.player_id for lot in self.board(seed=7)],
        )

    def test_a_different_seed_deals_a_different_board(self):
        self.assertNotEqual(
            [lot.player_id for lot in self.board(seed=7)],
            [lot.player_id for lot in self.board(seed=8)],
        )


if __name__ == "__main__":
    unittest.main()
