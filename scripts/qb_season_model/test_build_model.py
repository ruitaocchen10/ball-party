"""Tests for the build script's adapters.

The fit itself is tested in test_transform.py. What is covered here is the one
piece of reading the build does that is not a CSV: the ratings migration, whose
inserts are the finished values the fit is made from. A wrong parse there would
fit the wrong quarterbacks without anything failing, so it is worth a test.

Run with: python3 -m unittest discover scripts/qb_season_model
"""

import unittest

from build_model import parse_insert_rows, sql_literal

TABLE = "qb_season_builder_private.qb_seasons"


class ParseInsertRowsTest(unittest.TestCase):
    def sql(self, *lines):
        return (f"insert into {TABLE} (franchise_code, season, display_name, accuracy) values\n"
                + ",\n".join(f"  {line}" for line in lines) + ";\n\n")

    def test_reads_strings_and_integers_in_order(self):
        rows = parse_insert_rows(self.sql("('kan', 2018, 'Patrick Mahomes', 89)"), TABLE)
        self.assertEqual(rows, [("kan", 2018, "Patrick Mahomes", 89)])

    def test_a_doubled_quote_is_one_apostrophe(self):
        rows = parse_insert_rows(self.sql("('nor', 2010, 'Dan O''Brien', 61)"), TABLE)
        self.assertEqual(rows[0][2], "Dan O'Brien")

    def test_a_comma_inside_a_string_does_not_split_the_field(self):
        rows = parse_insert_rows(self.sql("('nor', 2010, 'Smith, Jr.', 61)"), TABLE)
        self.assertEqual(rows[0][2:], ("Smith, Jr.", 61))

    def test_null_and_decimals(self):
        sql = f"insert into {TABLE} (a, b, c) values\n  (null, 1.5, -3);\n"
        self.assertEqual(parse_insert_rows(sql, TABLE), [(None, 1.5, -3)])

    def test_every_insert_into_the_table_is_read_and_other_tables_are_not(self):
        sql = (self.sql("('a', 1, 'x', 1)") + self.sql("('b', 2, 'y', 2)")
               + "insert into qb_season_builder_private.team_seasons (a) values\n  ('z');\n")
        self.assertEqual([r[0] for r in parse_insert_rows(sql, TABLE)], ["a", "b"])

    def test_a_table_with_no_insert_is_no_rows(self):
        self.assertEqual(parse_insert_rows("select 1;\n", TABLE), [])


class SqlLiteralTest(unittest.TestCase):
    def test_literals(self):
        self.assertEqual(sql_literal(None), "null")
        self.assertEqual(sql_literal(True), "true")
        self.assertEqual(sql_literal(False), "false")
        self.assertEqual(sql_literal(7), "7")
        self.assertEqual(sql_literal(2.0), "2")
        self.assertEqual(sql_literal(0.1), "0.1")
        self.assertEqual(sql_literal("O'Brien"), "'O''Brien'")

    def test_a_float_survives_the_round_trip_through_text(self):
        for x in (0.1 + 0.2, 1 / 3, -1.4695858455634698, 1e-16, 123456789.123456789):
            self.assertEqual(float(sql_literal(x)), x)


if __name__ == "__main__":
    unittest.main()
