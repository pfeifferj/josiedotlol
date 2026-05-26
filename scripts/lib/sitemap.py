"""Generate sitemap.xml from the data context."""
from __future__ import annotations

from .config import OUTPUT_ROOT, SITE_URL


def render_sitemap(ctx: dict) -> str:
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
        "  <!-- Main pages -->",
    ]

    def url(loc: str, *, lastmod: str = "", changefreq: str = "", priority: str = "") -> None:
        lines.append("  <url>")
        lines.append(f"    <loc>{loc}</loc>")
        if lastmod:
            lines.append(f"    <lastmod>{lastmod}</lastmod>")
        if changefreq:
            lines.append(f"    <changefreq>{changefreq}</changefreq>")
        if priority:
            lines.append(f"    <priority>{priority}</priority>")
        lines.append("  </url>")

    url(f"{SITE_URL}/", changefreq="weekly", priority="1.0")
    url(f"{SITE_URL}/blog/", changefreq="weekly", priority="0.9")
    url(f"{SITE_URL}/talks/", changefreq="monthly", priority="0.9")
    url(f"{SITE_URL}/about/", changefreq="monthly", priority="0.9")

    for post in ctx["blog_posts"]:
        # External posts live on other domains; they belong in the RSS feed,
        # not in this sitemap.
        if post.get("external"):
            continue
        url(
            f"{SITE_URL}/blog/{post['slug']}.html",
            lastmod=post.get("date_iso", ""),
            changefreq="monthly",
            priority="0.8",
        )

    # Talk slides: one entry per conference that has a slides URL.
    for t in ctx["talks"]:
        for c in t.get("conferences") or []:
            slides = c.get("slides")
            if not slides:
                continue
            slide_url = slides if slides.startswith("http") else f"{SITE_URL}{slides}"
            url(slide_url, lastmod=t.get("date_iso", ""), changefreq="yearly", priority="0.7")

    lines.append("</urlset>")
    lines.append("")
    return "\n".join(lines)


def write_sitemap(ctx: dict) -> None:
    (OUTPUT_ROOT / "sitemap.xml").write_text(render_sitemap(ctx), encoding="utf-8")
    print("rendered sitemap.xml")
