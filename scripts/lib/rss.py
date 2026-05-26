"""Generate rss.xml from the data context."""
from __future__ import annotations

from datetime import datetime, timezone
from email.utils import format_datetime
from html import escape

from .config import OUTPUT_ROOT, SITE_URL


def _rfc822(date_iso: str) -> str:
    if not date_iso:
        return format_datetime(datetime.now(timezone.utc))
    # Accept YYYY-MM-DD or YYYY-MM (append -01 for parsing).
    candidate = date_iso if len(date_iso) >= 10 else f"{date_iso}-01"
    try:
        dt = datetime.strptime(candidate, "%Y-%m-%d")
    except ValueError:
        return format_datetime(datetime.now(timezone.utc))
    # Bash used `date -R` which emits the system's local zone. The previously
    # generated file shows +0100/+0200 (Zurich). Emit UTC: stable across hosts
    # and parsers accept any RFC822 zone.
    return format_datetime(dt.replace(tzinfo=timezone.utc))


def render_rss(ctx: dict) -> str:
    posts = ctx["blog_posts"]
    latest_date_iso = posts[0]["date_iso"] if posts else ""

    items: list[str] = []
    for post in posts:
        title = post["title"]
        link = post["url"] if post["external"] else f"{SITE_URL}/blog/{post['slug']}.html"
        if post["external"] and post.get("publication"):
            title = f"{title} (via {post['publication']})"
        items.append(
            "  <item>\n"
            f"    <title>{escape(title)}</title>\n"
            f"    <link>{escape(link)}</link>\n"
            f"    <description><![CDATA[{post.get('description','')}]]></description>\n"
            f"    <pubDate>{_rfc822(post.get('date_iso', ''))}</pubDate>\n"
            f"    <guid>{escape(link)}</guid>\n"
            "  </item>"
        )

    return (
        '<?xml version="1.0" encoding="UTF-8" ?>\n'
        '<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">\n'
        "<channel>\n"
        "  <title>Josephine Pfeiffer's Publications</title>\n"
        f"  <link>{SITE_URL}/</link>\n"
        "  <description>Publications by Josephine Pfeiffer</description>\n"
        f"  <lastBuildDate>{_rfc822(latest_date_iso)}</lastBuildDate>\n"
        f'  <atom:link href="{SITE_URL}/rss.xml" rel="self" type="application/rss+xml" />\n'
        "  \n"
        "  <!-- POSTS_START -->\n"
        + "\n".join(items) + "\n"
        "  <!-- POSTS_END -->\n"
        "\n"
        "</channel>\n"
        "</rss>\n"
    )


def write_rss(ctx: dict) -> None:
    (OUTPUT_ROOT / "rss.xml").write_text(render_rss(ctx), encoding="utf-8")
    print("rendered rss.xml")
