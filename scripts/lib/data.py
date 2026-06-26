"""Load every data source into a single context dict for templates."""
from __future__ import annotations

import json
import re
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

import yaml

from .config import BLOG_DIR, DATA_DIR, PERSON_ID, ROOT, SITE_URL, TALKS_DIR


FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n?(.*)$", re.DOTALL)
TOP_KEY_RE = re.compile(r"^([A-Za-z0-9_-]+):\s*(.*)$")


def _preprocess_yaml(text: str) -> str:
    """Force-quote top-level scalar values that contain unquoted colons.

    Talk and blog frontmatter is hand-written and often has lines like
    `title: Beyond CAS: Why the world needs another...` which is invalid YAML.
    The previous bash build read these with grep/sed and never tripped, so the
    files stay as-is and the loader normalises them before yaml.safe_load.
    """
    out = []
    for line in text.splitlines():
        if not line.strip():
            out.append(line)
            continue
        if line[0] in " \t-":
            out.append(line)
            continue
        m = TOP_KEY_RE.match(line)
        if not m:
            out.append(line)
            continue
        key, val = m.group(1), m.group(2).rstrip()
        if not val or val[0] in "\"'[{|>" or val in ("true", "false", "null", "~"):
            out.append(line)
            continue
        # Date-like or pure number stays bare.
        bare = val.replace("-", "").replace(".", "").replace(":", "")
        if bare.isdigit():
            out.append(line)
            continue
        safe = val.replace("\\", "\\\\").replace("\"", "\\\"")
        out.append(f'{key}: "{safe}"')
    return "\n".join(out)


def parse_frontmatter(path: Path) -> tuple[dict[str, Any], str]:
    text = path.read_text(encoding="utf-8")
    m = FRONTMATTER_RE.match(text)
    if not m:
        return {}, text
    meta = yaml.safe_load(_preprocess_yaml(m.group(1))) or {}
    body = m.group(2)
    return meta, body


def _data_files(subdir: str) -> list[Path]:
    d = DATA_DIR / subdir
    if not d.is_dir():
        return []
    return sorted(p for p in d.glob("*.md") if p.name != "template.md")


def load_topics() -> list[dict[str, str]]:
    path = DATA_DIR / "topics.yml"
    if not path.is_file():
        return []
    doc = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    return list(doc.get("topics", []))


def load_projects() -> list[dict[str, Any]]:
    out = []
    for p in _data_files("projects"):
        meta, body = parse_frontmatter(p)
        meta["description"] = first_paragraph(body)
        meta["slug"] = p.stem
        out.append(meta)
    return out


def load_faq() -> list[dict[str, Any]]:
    out = []
    for p in _data_files("faq"):
        meta, body = parse_frontmatter(p)
        meta["answer_md"] = collapse_paragraphs(body).strip()
        meta["answer_plain"] = strip_md_links(meta["answer_md"])
        out.append(meta)
    return out


def load_memberships() -> list[dict[str, Any]]:
    out = []
    for p in _data_files("memberships"):
        meta, _ = parse_frontmatter(p)
        out.append(meta)
    return out


def load_publications() -> list[dict[str, Any]]:
    out = []
    for p in _data_files("publications"):
        meta, body = parse_frontmatter(p)
        meta.setdefault("type", "Article")
        meta["description"] = first_paragraph(body)
        out.append(meta)
    return out


def load_work_history() -> list[dict[str, Any]]:
    """Career timeline, ordered newest first via numeric filename prefix."""
    out = []
    for p in _data_files("work-history"):
        meta, body = parse_frontmatter(p)
        meta["slug"] = p.stem
        meta["description"] = first_paragraph(body) or meta.get("focus", "")
        meta["start_date"] = normalize_date(meta.get("start_date"))
        meta["end_date"] = normalize_date(meta.get("end_date"))
        meta["current"] = not meta["end_date"]
        out.append(meta)
    return out


def load_testimonials() -> list[dict[str, Any]]:
    out = []
    for p in _data_files("testimonials"):
        meta, body = parse_frontmatter(p)
        meta["slug"] = p.stem
        meta["body"] = collapse_paragraphs(body).strip()
        out.append(meta)
    return out


def load_credentials() -> list[dict[str, Any]]:
    path = DATA_DIR / "credly-cache.json"
    if not path.is_file():
        return []
    doc = json.loads(path.read_text(encoding="utf-8"))
    items = doc.get("data", [])
    items = [b for b in items if b.get("state") == "accepted"]
    items = [
        b for b in items
        if (b.get("badge_template") or {}).get("type_category") in ("Certification", "Learning")
    ]
    items.sort(key=lambda b: b.get("issued_at_date", ""), reverse=True)
    out = []
    for b in items:
        tpl = b.get("badge_template") or {}
        issuer = (tpl.get("issuer") or {}).get("entities") or [{}]
        issuer_name = (issuer[0].get("entity") or {}).get("name") if issuer else None
        out.append({
            "name": tpl.get("name", ""),
            "year": (b.get("issued_at_date", "") or "")[:4],
            "issued_at_date": b.get("issued_at_date", ""),
            "issuer": issuer_name,
            "url": f"https://www.credly.com/badges/{b.get('id')}" if b.get("id") else None,
        })
    return out


def load_blog_posts() -> list[dict[str, Any]]:
    """Parse blog/*.md frontmatter. Body parsing belongs in lib.markdown."""
    out = []
    for p in sorted(BLOG_DIR.glob("*.md")):
        meta, body = parse_frontmatter(p)
        meta["slug"] = p.stem
        meta["body_md"] = body
        meta["external"] = bool(meta.get("external_post"))
        meta["url"] = meta.get("external_url") if meta["external"] else f"/blog/{p.stem}.html"
        meta["canonical_url"] = (
            meta["url"] if meta["external"] else f"{SITE_URL}/blog/{p.stem}.html"
        )
        meta["publication"] = meta.get("external_publication") or ""
        meta["date_iso"] = normalize_date(meta.get("date"))
        out.append(meta)
    out.sort(key=lambda p: p.get("date_iso") or "", reverse=True)
    return out


def load_talks() -> list[dict[str, Any]]:
    out = []
    for p in sorted(TALKS_DIR.glob("*.md")):
        if p.name in ("template.md", "index.md"):
            continue
        meta, _ = parse_frontmatter(p)
        meta["slug"] = p.stem
        meta["date_iso"] = normalize_date(meta.get("date"))
        confs = meta.get("conferences") or []
        for c in confs:
            c["date"] = normalize_date(c.get("date"))
        confs.sort(key=lambda c: c.get("date") or "", reverse=True)
        meta["conferences"] = confs
        latest = confs[0]["date"] if confs else meta["date_iso"]
        meta["upcoming"] = bool(latest) and latest >= _today()
        out.append(meta)
    # Sort by top-level talk date desc (matches bash output).
    out.sort(key=lambda t: t.get("date_iso") or "", reverse=True)
    return out


def _today() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def first_paragraph(body: str) -> str:
    parts = body.strip().split("\n\n", 1)
    return parts[0].replace("\n", " ").strip() if parts else ""


def collapse_paragraphs(body: str) -> str:
    """Collapse hard wraps inside a single paragraph to one line."""
    return " ".join(line for line in body.splitlines() if line.strip())


def strip_md_links(text: str) -> str:
    return re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r"\1 (\2)", text)


def normalize_date(d: Any) -> str:
    if isinstance(d, (date, datetime)):
        return d.strftime("%Y-%m-%d")
    if not d:
        return ""
    return str(d)


# Bio as visually-wrapped lines. Empty strings mark paragraph breaks. The
# homepage iterates this list to render <br />-broken text in the terminal
# aesthetic; every other consumer (llms.txt, about page, JSON-LD description)
# derives a single-paragraph string by joining non-empty lines with a space.
_BIO_LINES = (
    "josie works on infrastructure and security. she spends",
    "work hours on linux userspace networking, free time on",
    "porting distros to weird architectures, and contributing",
    "to CNCF projects.",
    "",
    "she unironically thinks s390x is cool and will argue",
    "about it.",
    "",
    "occasionally writes crystal, and likes electronics",
    "with transparent cases.",
)


def person() -> dict[str, Any]:
    return {
        "id": PERSON_ID,
        "name": "Josephine Pfeiffer",
        "given_name": "Josephine",
        "family_name": "Pfeiffer",
        "job_title": "Senior Software Engineer",
        "works_for": "Red Hat",
        "address": {"locality": "Zurich", "country": "Switzerland"},
        "display_location": "Zurich / London",
        "email": "hi@josie.lol",
        "image": f"{SITE_URL}/me.jpg",
        "url": f"{SITE_URL}/",
        "same_as": [
            "https://github.com/pfeifferj",
            "https://gitlab.com/users/josie",
            "https://gitlab.gnome.org/josie",
            "https://gitlab.freedesktop.org/josie",
            "https://accounts.fedoraproject.org/user/josie/",
            "https://fedoraproject.org/wiki/User:Josie",
            "https://www.linkedin.com/in/josephine-pfeiffer/",
            "https://www.credly.com/users/pfeifferj",
        ],
        "bio_lines": list(_BIO_LINES),
        "bio_paragraph": " ".join(line for line in _BIO_LINES if line),
        "tagline_description": (
            "generally competent computer magician in the areas of infrastructure, "
            "security, and developer experience."
        ),
    }


def load_context() -> dict[str, Any]:
    return {
        "site": {"url": SITE_URL, "person_id": PERSON_ID, "root": str(ROOT)},
        "person": person(),
        "topics": load_topics(),
        "projects": load_projects(),
        "faq": load_faq(),
        "memberships": load_memberships(),
        "publications": load_publications(),
        "work_history": load_work_history(),
        "testimonials": load_testimonials(),
        "credentials": load_credentials(),
        "blog_posts": load_blog_posts(),
        "talks": load_talks(),
        "build": {"now": datetime.now(timezone.utc).strftime("%Y-%m-%d")},
    }
