#!/usr/bin/env python3
"""Sync the hosted project's exposed Data API schemas with supabase/config.toml.

config.toml's `api.schemas` is already the file people edit when a new game
adds its own Postgres schema -- it has to be, since that's what exposes the
schema to the *local* Data API too. This script is CI's half: it takes that
same list and pushes it to the hosted project after migrations deploy, via
the Management API's postgrest-config endpoint.

Deliberately narrow: it GETs the project's current postgrest config, changes
only `db_schema`, and PATCHes the whole object back -- so db_extra_search_path,
max_rows, and anything else PostgREST tracks here are preserved untouched.
This does not touch auth/db/storage project settings at all; those have
diverged from config.toml's local-dev defaults on purpose (site_url, Apple
sign-in, the iOS redirect URL, pooler sizing) and `supabase config push`
pushing all of them is exactly what this script exists to avoid needing.
"""

import json
import os
import re
import sys
import urllib.error
import urllib.request

CONFIG_PATH = "supabase/config.toml"
MANAGEMENT_API = "https://api.supabase.com/v1"


def desired_schemas() -> list[str]:
    with open(CONFIG_PATH, encoding="utf-8") as f:
        content = f.read()

    match = re.search(r"(?m)^schemas\s*=\s*\[(.*?)\]", content)
    if not match:
        sys.exit(f"could not find `schemas = [...]` under [api] in {CONFIG_PATH}")

    return [s.strip().strip('"') for s in match.group(1).split(",") if s.strip()]


def api_request(method: str, path: str, token: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        f"{MANAGEMENT_API}{path}",
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path} failed: {e.code} {e.read().decode()}")


def main() -> None:
    token = os.environ["SUPABASE_ACCESS_TOKEN"]
    ref = os.environ["SUPABASE_PROJECT_REF"]

    desired = desired_schemas()
    current = api_request("GET", f"/projects/{ref}/postgrest", token)
    current_schemas = [s.strip() for s in current.get("db_schema", "").split(",") if s.strip()]

    # Order isn't meaningful to PostgREST, and the hosted list is appended to
    # by the dashboard, so compare as sets or every run reports false drift.
    if set(current_schemas) == set(desired):
        print(f"Exposed schemas already match config.toml: {desired}")
        return

    print("Exposed schemas have drifted from config.toml:")
    print(f"  prod:        {current_schemas}")
    print(f"  config.toml: {desired}")
    print("Updating the Data API's exposed schemas...")

    current["db_schema"] = ",".join(desired)
    # The GET returns unset fields as null (e.g. db_pool), which the PATCH
    # validator rejects as "expected number, received null". Omitting them
    # leaves those settings as they are.
    body = {k: v for k, v in current.items() if v is not None}
    api_request("PATCH", f"/projects/{ref}/postgrest", token, body)
    print(f"Updated. Exposed schemas are now: {desired}")


if __name__ == "__main__":
    main()
