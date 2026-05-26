"""Generate .well-known/security.txt with rolling expiry.

Regenerates only when the current Expires header is within 60 days of now
(or the file is missing). New Expires is now + 11 months UTC.
"""
from __future__ import annotations

import re
from datetime import datetime, timedelta, timezone

from .config import OUTPUT_ROOT, SITE_URL


_WELL_KNOWN = OUTPUT_ROOT / ".well-known"
_FILE = _WELL_KNOWN / "security.txt"
_EXPIRES_RE = re.compile(r"^Expires:\s*(\S+)\s*$", re.MULTILINE)


def _needs_regen() -> tuple[bool, str | None]:
    if not _FILE.exists():
        return True, None
    text = _FILE.read_text(encoding="utf-8")
    m = _EXPIRES_RE.search(text)
    if not m:
        return True, None
    try:
        current = datetime.fromisoformat(m.group(1).replace("Z", "+00:00"))
    except ValueError:
        return True, None
    cutoff = datetime.now(timezone.utc) + timedelta(days=60)
    return (current < cutoff), m.group(1)


def write_security_txt() -> None:
    regen, current = _needs_regen()
    if not regen:
        print(f".well-known/security.txt current (Expires: {current})")
        return
    expires = (datetime.now(timezone.utc) + timedelta(days=11 * 30)).strftime(
        "%Y-%m-%dT00:00:00Z"
    )
    _WELL_KNOWN.mkdir(parents=True, exist_ok=True)
    _FILE.write_text(
        "Contact: mailto:hi@josie.lol\n"
        "Contact: https://go.josie.lol/signal\n"
        f"Expires: {expires}\n"
        "Preferred-Languages: en\n"
        f"Canonical: {SITE_URL}/.well-known/security.txt\n",
        encoding="utf-8",
    )
    print(f"regenerated .well-known/security.txt (Expires: {expires})")
