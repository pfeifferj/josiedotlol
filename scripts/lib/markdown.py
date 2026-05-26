"""Render blog-post markdown bodies to HTML.

Output is consumed via `{{ post.body_html | safe }}` in the post template,
which bypasses jinja autoescape. Inputs are author-controlled markdown
files under blog/ (no user-submitted content), so raw HTML in posts is
intentional. Do not feed untrusted markdown through this renderer without
adding a sanitizer (e.g. bleach).
"""
from __future__ import annotations

import markdown as md


def render_post_body(text: str) -> str:
    """Render a blog post body. Returns an HTML fragment, no <html>/<body>."""
    converter = md.Markdown(
        extensions=["fenced_code", "tables", "footnotes", "attr_list", "sane_lists"],
        output_format="html5",
    )
    return converter.convert(text)
