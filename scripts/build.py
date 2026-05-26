#!/usr/bin/env python3
"""Static-site builder for josie.lol. Entry point: `python3 scripts/build.py`."""
from __future__ import annotations

import argparse
import json
import sys

from lib import jsonld
from lib.credly import refresh as refresh_credly
from lib.data import load_context
from lib.llms import write_llms
from lib.markdown import render_post_body
from lib.render import build_env, render, write_output
from lib.rss import write_rss
from lib.security_txt import write_security_txt
from lib.sitemap import write_sitemap


def _talk_conference_count(talks) -> int:
    names = set()
    for t in talks:
        for c in t.get("conferences") or []:
            n = c.get("name")
            if n:
                names.add(n.strip())
    return len(names)


def render_about(env, ctx) -> None:
    extra = {
        "aboutpage_jsonld": jsonld.aboutpage(ctx),
        "knows_about_jsonld": jsonld.knows_about(ctx),
        "projects_jsonld": jsonld.projects(ctx),
        "work_history_jsonld": jsonld.work_history(ctx),
        "faq_jsonld": jsonld.faq(ctx),
        "talks_count": len(ctx["talks"]),
        "conferences_count": _talk_conference_count(ctx["talks"]),
    }
    html = render(env, "about/index.html.j2", {**ctx, **extra})
    write_output("about/index.html", html)
    print("rendered about/index.html")


def render_blog(env, ctx) -> None:
    html = render(env, "blog/index.html.j2", ctx)
    write_output("blog/index.html", html)
    print("rendered blog/index.html")

    for post in ctx["blog_posts"]:
        if post.get("external"):
            continue
        post = dict(post)  # don't mutate the shared ctx entry
        post["body_html"] = render_post_body(post.get("body_md", ""))
        page_ctx = {**ctx, "post": post, "post_jsonld": jsonld.blog_posting(post)}
        html = render(env, "blog/post.html.j2", page_ctx)
        write_output(f"blog/{post['slug']}.html", html)
        print(f"rendered blog/{post['slug']}.html")


def render_talks(env, ctx) -> None:
    extra = {"talks_jsonld": jsonld.talks_graph(ctx)}
    html = render(env, "talks/index.html.j2", {**ctx, **extra})
    write_output("talks/index.html", html)
    print("rendered talks/index.html")


def render_index(env, ctx) -> None:
    extra = {
        "website_jsonld": jsonld.website(ctx),
        "knows_about_jsonld": jsonld.knows_about(ctx),
        "has_credential_jsonld": jsonld.has_credential(ctx),
        "member_of_jsonld": jsonld.member_of(ctx),
        "published_media_jsonld": jsonld.published_media(ctx),
        "work_performed_jsonld": jsonld.work_performed(ctx),
        "reviews_jsonld": jsonld.reviews(ctx),
    }
    html = render(env, "index.html.j2", {**ctx, **extra})
    write_output("index.html", html)
    print("rendered index.html")


def main() -> int:
    parser = argparse.ArgumentParser(description="josie.lol site builder")
    parser.add_argument(
        "--dump-context",
        action="store_true",
        help="Print the loaded data context as JSON and exit.",
    )
    args = parser.parse_args()

    refresh_credly()
    ctx = load_context()

    if args.dump_context:
        json.dump(ctx, sys.stdout, indent=2, default=str)
        sys.stdout.write("\n")
        return 0

    env = build_env()
    render_index(env, ctx)
    render_talks(env, ctx)
    render_about(env, ctx)
    render_blog(env, ctx)
    write_sitemap(ctx)
    write_rss(ctx)
    write_llms(ctx)
    write_security_txt()
    return 0


if __name__ == "__main__":
    # Allow `python3 scripts/build.py` from anywhere by ensuring the lib/
    # package resolves relative to this file.
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    sys.exit(main())
