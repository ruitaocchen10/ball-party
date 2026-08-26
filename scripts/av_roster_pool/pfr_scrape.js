// Pro Football Reference roster scrape: procedure and reusable snippets.
//
// WHY THIS ISN'T A PYTHON SCRIPT: PFR sits behind a Cloudflare JS challenge
// that no stdlib HTTP client (or `requests`) can pass — a plain fetch gets an
// interstitial "Just a moment..." page, never the roster. This has to run
// from inside a real browser tab that has already passed the challenge by
// loading a page normally. There is no way around that with pure Python.
//
// PFR also rate-limits explicitly: 20 requests/minute, or the session is
// "jailed" for up to a day (sports-reference.com/bot-traffic.html). Every
// loop below paces requests at one per 3.2 seconds — comfortably under that
// limit, not right up against it.
//
// One more real quirk, easy to miss: PFR renders the full roster table
// (id="roster") inside an HTML comment in the raw response, and only
// unwraps it into real markup via its own page-load JavaScript. A `fetch()`
// of the raw page text will not see it — the unwrap step below is required,
// not optional. (This is why `document.querySelectorAll('#roster ...')`
// works fine when you've navigated to the page normally, but silently
// returns zero rows if you `fetch()` the same URL's text and parse it
// naively.)
//
// -------------------------------------------------------------------------
// PROCEDURE (this is what was actually run to produce the 2020-2025 cache):
//
// 1. Navigate a real tab to any pro-football-reference.com page once, so
//    Cloudflare's challenge is passed and the session cookie is set.
// 2. Paste FETCH_SEASONS (below) into that tab's console (or run it via
//    browser automation's javascript_tool), with SEASONS and CODES set to
//    whatever range you're extending the pool to cover. It accumulates into
//    `window.__pfrBuf` and checkpoints to `localStorage['pfrBuf']` after
//    every team, so a dropped connection loses at most one team-season, not
//    the whole run.
//    - If the run is long, the tool executing this may time out waiting for
//      a response well before the script itself finishes — that's a
//      round-trip timeout, not a script failure. The script keeps running
//      in the page in the background; just poll `window.__pfrBuf.length`
//      (or `JSON.parse(localStorage.pfrBuf).length`) again after a pause.
// 3. Once done, run DOWNLOAD (below) *in a fresh tab* navigated to the same
//    origin (localStorage is shared across tabs on one origin, so the data
//    is visible there too). This matters: Chrome silently drops a second
//    unprompted download triggered from a tab that already auto-downloaded
//    once, with no visible error — a fresh tab hasn't spent that allowance
//    yet. This is how the download actually lands in ~/Downloads instead of
//    silently vanishing.
// 4. Move the downloaded file to `.cache/pfr_<first>_<last>.txt` (the path
//    build_pool.py's `--pfr-cache` expects, by default
//    `.cache/pfr_2020_2025.txt`), then run build_pool.py normally.
//
// Output format: one line per player-season, `code|season|player_id|name|pos|av`.

const SEASONS = [2020, 2021, 2022, 2023, 2024, 2025]; // edit when extending

// PFR's own stable franchise codes, confirmed against
// pro-football-reference.com/teams/index.htm — one code per active
// franchise, unaffected by relocations (e.g. "oti" covers both the Houston
// Oilers and the Tennessee Titans eras of that one franchise).
const CODES = [
  "crd", "atl", "rav", "buf", "car", "chi", "cin", "cle", "dal", "den",
  "det", "gnb", "htx", "clt", "jax", "kan", "rai", "sdg", "ram", "mia",
  "min", "nwe", "nor", "nyg", "nyj", "phi", "pit", "sfo", "sea", "tam",
  "oti", "was",
];

// eslint-disable-next-line no-unused-vars
const FETCH_SEASONS = async () => {
  window.__pfrBuf = JSON.parse(localStorage.getItem("pfrBuf") || "[]");
  window.__pfrErrors = window.__pfrErrors || [];
  const done = new Set(window.__pfrBuf.map((l) => {
    const [c, y] = l.split("|");
    return c + "_" + y;
  }));
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  for (const year of SEASONS) {
    for (const code of CODES) {
      if (done.has(code + "_" + year)) continue;
      const url = `https://www.pro-football-reference.com/teams/${code}/${year}_roster.htm`;
      try {
        const res = await fetch(url);
        if (!res.ok) {
          window.__pfrErrors.push(code + year + ":" + res.status);
          await sleep(3200);
          continue;
        }
        const html = await res.text();
        // Unwrap the comment-hidden roster table — see the note above.
        const unwrapped = html.replace(/<!--([\s\S]*?)-->/g, (m, inner) =>
          inner.includes('id="roster"') ? inner : m);
        const doc = new DOMParser().parseFromString(unwrapped, "text/html");
        const rows = [...doc.querySelectorAll("#roster tbody tr")];
        for (const r of rows) {
          const get = (s) => r.querySelector(`[data-stat="${s}"]`);
          const p = get("player");
          const id = p ? p.getAttribute("data-append-csv") : "";
          if (!id) continue; // header/divider rows carry no player id
          const name = p.textContent.trim();
          const pos = get("pos")?.textContent.trim() || "";
          const av = get("av")?.textContent.trim() || "";
          window.__pfrBuf.push(`${code}|${year}|${id}|${name}|${pos}|${av}`);
        }
        done.add(code + "_" + year);
        localStorage.setItem("pfrBuf", JSON.stringify(window.__pfrBuf));
      } catch (e) {
        window.__pfrErrors.push(code + year + ":" + e.message);
      }
      await sleep(3200); // ~19/min, under PFR's 20/min limit
    }
  }
};
FETCH_SEASONS();

// eslint-disable-next-line no-unused-vars
const DOWNLOAD = () => {
  const arr = JSON.parse(localStorage.getItem("pfrBuf"));
  const text = arr.join("\n");
  const blob = new Blob([text], { type: "text/plain" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = "pfr_scrape.txt";
  document.body.appendChild(a);
  a.click();
  a.remove();
  return `triggered, rows=${arr.length}`;
};
