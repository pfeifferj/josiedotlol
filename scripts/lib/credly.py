"""Refresh data/credly-cache.json from the Credly badges API.

Best-effort network call. Skips entirely when SKIP_CREDLY is set or when the
cache is fresh within CACHE_TTL. On any failure (no network, bad response,
empty data) the existing cache stays in place so the build still succeeds.
"""
from __future__ import annotations

import json
import os
import time

import requests

from .config import ROOT


CACHE = ROOT / "data" / "credly-cache.json"
DEFAULT_USER = "pfeifferj"
CACHE_TTL_SECONDS = 24 * 60 * 60
REQUEST_TIMEOUT = 5


def refresh() -> None:
    if os.environ.get("SKIP_CREDLY"):
        print("Credly fetch skipped (SKIP_CREDLY set)")
        return

    if CACHE.is_file() and (time.time() - CACHE.stat().st_mtime) < CACHE_TTL_SECONDS:
        print(f"Credly cache fresh; skipping fetch ({CACHE})")
        return

    user = os.environ.get("CREDLY_USER", DEFAULT_USER)
    url = f"https://www.credly.com/users/{user}/badges.json?sort=most_popular"

    try:
        resp = requests.get(
            url,
            headers={"User-Agent": "Mozilla/5.0"},
            timeout=REQUEST_TIMEOUT,
        )
        resp.raise_for_status()
        doc = resp.json()
    except (requests.RequestException, ValueError) as e:
        if CACHE.is_file():
            print(f"Credly fetch failed ({e}); using cached {CACHE}")
        else:
            print(f"Credly fetch failed ({e}); no cache available")
        return

    if not isinstance(doc.get("data"), list) or not doc["data"]:
        print(f"Credly returned empty data; keeping cached {CACHE}")
        return

    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(
        json.dumps(doc, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    print(f"Fetched Credly badges (cached to {CACHE})")
