"""Jinja2 environment and a thin render helper."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import html
import re

import jinja2
from markupsafe import Markup

from .config import OUTPUT_ROOT, TEMPLATES_DIR
from .data import strip_md_links


_SAFE_URL_RE = re.compile(r"^(?:https?:|mailto:|/|#|\?)", re.IGNORECASE)

# Acronyms (>=2 consecutive uppercase letters) and tokens with digits get
# preserved when lowercasing prose. Examples that stay: GPU, IBM, SGX,
# RDMA, FOSDEM, vLLM (contains LLM), MacVLAN (contains VLAN), H100, s390x.
# Examples that lowercase: OpenShift -> openshift, Senior Software Engineer
# -> senior software engineer, Red Hat -> red hat.
_ACRONYM_RE = re.compile(r"[A-Z]{2,}|[A-Za-z]*\d[A-Za-z0-9]*")


def _lower_keep_acronyms(text: str) -> str:
    if not text:
        return ""
    out: list[str] = []
    pos = 0
    for m in _ACRONYM_RE.finditer(text):
        out.append(text[pos:m.start()].lower())
        out.append(m.group(0))
        pos = m.end()
    out.append(text[pos:].lower())
    return "".join(out)


def _tojson_ld(value: Any) -> str:
    """JSON serializer for JSON-LD <script> contexts.

    json.dumps does not escape `<`, so a `</script>` substring in any string
    value breaks out of the surrounding <script type="application/ld+json">
    tag. The unicode-escape replacements keep the JSON semantically identical
    while preventing script-context escape.
    """
    raw = json.dumps(value, ensure_ascii=False, indent=2)
    return raw.replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")


def _safe_href(url: str) -> str:
    """Return url if its scheme is in the allowlist, else `#`.

    Blocks javascript: and data: URIs (the two common XSS sinks in markdown
    href context). Relative URLs, fragments, mailto:, and http(s) pass.
    """
    return url if _SAFE_URL_RE.match(url.strip()) else "#"


def _markdown_inline(text: str) -> Markup:
    """Render inline markdown links to <a> tags. HTML-escape everything else."""
    out: list[str] = []
    last = 0
    for m in re.finditer(r"\[([^\]]+)\]\(([^)]+)\)", text):
        out.append(html.escape(text[last:m.start()]))
        out.append('<a href="')
        out.append(html.escape(_safe_href(m.group(2)), quote=True))
        out.append(
            '" class="text-purple-500 dark:text-purple-400 no-underline '
            'transition-colors duration-200 hover:text-white hover:underline">'
        )
        out.append(html.escape(m.group(1)))
        out.append("</a>")
        last = m.end()
    out.append(html.escape(text[last:]))
    return Markup("".join(out))


def build_env() -> jinja2.Environment:
    env = jinja2.Environment(
        loader=jinja2.FileSystemLoader(str(TEMPLATES_DIR)),
        autoescape=jinja2.select_autoescape(["html", "html.j2", "xml", "xml.j2"]),
        trim_blocks=True,
        lstrip_blocks=True,
        keep_trailing_newline=True,
    )
    env.filters["tojson_ld"] = _tojson_ld
    env.filters["markdown_inline"] = _markdown_inline
    env.filters["strip_md_links"] = strip_md_links
    env.filters["lower_keep_acronyms"] = _lower_keep_acronyms
    return env


def render(env: jinja2.Environment, template_name: str, ctx: dict) -> str:
    return env.get_template(template_name).render(**ctx)


def write_output(rel_path: str, content: str) -> Path:
    out = OUTPUT_ROOT / rel_path
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(content, encoding="utf-8")
    return out
