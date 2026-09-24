"""The real tuning for QB Season Builder's ratings, and the sanity checks that
guard it.

Everything here is an input to `transform.transform` and to the build's guards,
not a constant of the algorithm: retune by editing this file and rebuilding a
new data migration. The Madden / stats weights are the table from issue #72,
recorded as the go defaults in docs/games/qb_season_builder_madden_data.md §4.
On a no-go the Madden column is 0 (`STAT_ONLY`), and nothing downstream changes.
"""

from transform import CAST, Config, Expectation

# (Madden, stats), per slot.
WEIGHTS = {
    "mobility": (70, 30),
    "arm_talent": (80, 20),
    "build": (50, 50),
    "accuracy": (50, 50),
    "iq": (60, 40),
    CAST: (50, 50),
}

# The stat-only fallback: the Madden column zeroed, per the recorded no-go path.
STAT_ONLY = {slot: (0, stats) for slot, (_madden, stats) in WEIGHTS.items()}

DEFAULT_CONFIG = Config(
    min_attempts=150,
    weights=WEIGHTS,
    # A season's worst rated quarterback lands at the floor and its best at the
    # ceiling. 25 keeps a qualifying starter from ever reading as a zero.
    value_floor=25,
    value_ceiling=99,
    # Madden attributes are the dataset's own column names. Build leans on the
    # physical and durability ratings, not height and weight, which the stat
    # side already carries.
    madden_attrs={
        "accuracy": {"throwaccuracyshort": 0.35, "throwaccuracymid": 0.40,
                     "throwaccuracydeep": 0.25},
        "arm_talent": {"throwpower": 0.70, "throwaccuracydeep": 0.30},
        "mobility": {"speed": 0.35, "acceleration": 0.35, "agility": 0.30},
        "iq": {"awareness": 0.70, "playaction": 0.15, "throwonrun": 0.15},
        "build": {"strength": 0.25, "toughness": 0.30, "injury": 0.30, "stamina": 0.15},
    },
    # Stat proxies limited to what the whole 2006-2025 weekly file carries. The
    # spec's deep-ball rate is completions of 20+ yards per attempt here; third-
    # down EPA and scrambles are not in the weekly file. IQ is mostly passing EPA
    # per dropback (nflverse's qb_epa, sacks included; ESPN's QBR is not in the
    # feed), the best single read on decisions in the weekly file, with the
    # turnover and sack rates as a small share. Mobility leans on rushing
    # efficiency. First-down rate per carry is deliberately not a Mobility
    # input: it rewards sneaks.
    stat_metrics={
        "accuracy": {"comp_pct": 0.35, "cpoe": 0.65},
        "arm_talent": {"air_yards_per_att": 0.55, "explosive_rate": 0.45},
        "mobility": {"rush_ypc": 0.50, "rush_epa_per_game": 0.50},
        "iq": {"epa_per_dropback": 0.60, "sack_rate": 0.15, "int_rate": 0.15,
               "fumble_rate": 0.10},
        "build": {"height": 0.40, "weight": 0.40, "durability": 0.20},
    },
    # Prior sample sizes: a 150-attempt season counts about as much as the
    # league rate; a full season barely moves.
    shrinkage={
        "comp_pct": 150, "cpoe": 150, "air_yards_per_att": 150, "explosive_rate": 150,
        "epa_per_dropback": 200, "int_rate": 200, "sack_rate": 200, "fumble_rate": 250,
        "rush_ypc": 40, "rush_epa_per_game": 4,
    },
    cast_offense_share=0.70,
    # slot category -> (unit, top-N players counted, weight within the unit).
    cast_slots={
        "WR": ("offense", 3, 0.35),
        "TE": ("offense", 1, 0.10),
        "RB": ("offense", 1, 0.10),
        "OL": ("offense", 5, 0.45),
        "DL": ("defense", 4, 0.35),
        "LB": ("defense", 3, 0.20),
        "CB": ("defense", 3, 0.25),
        "S": ("defense", 2, 0.20),
    },
    cast_attr="overall",
)

# Known-quarterback sanity checks (issue #72, user story 50). Each is a band a
# football fan would sign off on before looking at the number, not a value fitted
# to whatever the formulas produced; a build that lands outside one is a bad
# blend, and stops. Player ids are Pro Football Reference's.
EXPECTATIONS = [
    # A mobile quarterback stays mobile in a season his offense barely ran him:
    # the Madden side is what keeps talent from being read off usage.
    Expectation("JackLa00", 2019, "mobility", 90, 99, note="record-setting runner"),
    Expectation("JackLa00", 2023, "mobility", 80, 99, note="mobile MVP"),
    Expectation("VickMi00", 2010, "mobility", 80, 99, note="the original"),
    Expectation("NewtCa00", 2015, "mobility", 75, 99, note="MVP season"),
    Expectation("WilsRu00", 2013, "mobility", 70, 99, note="scrambler"),
    Expectation("MurrKy00", 2021, "mobility", 75, 99, note="dual threat in a pass-first year"),
    Expectation("AlleJo02", 2019, "mobility", 65, 99, note="dual threat, 2019 rookie-contract year"),
    Expectation("MannPe00", 2013, "mobility", 20, 55, note="pocket statue"),
    Expectation("RivePh00", 2011, "mobility", 20, 55, note="pocket passer"),
    Expectation("MannEl00", 2011, "mobility", 20, 55, note="pocket passer"),
    Expectation("BreeDr00", 2011, "mobility", 20, 65, note="pocket passer"),
    # Accuracy and arm are different things.
    Expectation("BreeDr00", 2011, "accuracy", 88, 99, note="the accuracy benchmark"),
    Expectation("BradTo00", 2007, "accuracy", 85, 99, note="50-TD season"),
    Expectation("RodgAa00", 2011, "accuracy", 88, 99, note="122.5 passer rating"),
    Expectation("MahoPa00", 2018, "arm_talent", 88, 99, note="the arm"),
    Expectation("AlleJo02", 2020, "arm_talent", 82, 99, note="cannon"),
    Expectation("BreeDr00", 2011, "arm_talent", 20, 78, note="accurate, not a cannon"),
    Expectation("MannPe00", 2013, "iq", 90, 99, note="the pre-snap mind"),
    Expectation("BradTo00", 2007, "iq", 90, 99, note="ball security and reads"),
    # The Supporting Cast, from what a fan remembers of the rosters.
    Expectation("", 2007, CAST, 80, 99, franchise_code="nwe", note="Moss, Welker, Brady's line, Seymour"),
    Expectation("", 2018, CAST, 75, 99, franchise_code="ram", note="Gurley, Woods, Cooks, Donald, Ramsey"),
    Expectation("", 2013, CAST, 70, 99, franchise_code="den", note="Thomas, Welker, Decker, Julius Thomas"),
    Expectation("", 2007, CAST, 0, 50, franchise_code="mia", note="1-15"),
    Expectation("", 2008, CAST, 0, 55, franchise_code="det", note="0-16"),
]

# Madden's own position labels -> the AV pool's slot categories, for the seasons
# whose rosters can only be read off Madden. Later editions fold the secondary
# into one `DB` label; it cannot be split into corners and safeties, so it counts
# at CB and those seasons have no Safety slot.
MADDEN_SLOT_OF = {
    "WR": "WR", "TE": "TE", "RB": "RB", "FB": "RB", "HB": "RB",
    "OL": "OL", "T": "OL", "G": "OL", "C": "OL", "OT": "OL", "OG": "OL",
    "DL": "DL", "DE": "DL", "DT": "DL", "NT": "DL",
    "LB": "LB", "OLB": "LB", "ILB": "LB", "MLB": "LB",
    "CB": "CB", "DB": "CB", "S": "S", "FS": "S", "SS": "S",
}
