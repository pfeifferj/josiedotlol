"""Build schema.org JSON-LD payloads from the data context dict.

Each function returns a plain dict ready for json.dumps. Templates render
these via the tojson_ld filter. Empty/falsy fields are stripped so the
output matches the prior `jq with_entries(select(.value != null and .value != ""))`
behavior.
"""
from __future__ import annotations

from typing import Any

from .config import PERSON_ID, SITE_URL


def _strip(d: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in d.items() if v not in (None, "", {}, [])}


def aboutpage(_ctx: dict) -> dict:
    return {
        "@context": "https://schema.org",
        "@type": "AboutPage",
        "@id": f"{SITE_URL}/about/",
        "url": f"{SITE_URL}/about/",
        "name": "About Josephine Pfeiffer",
        "description": (
            "Senior Software Engineer at Red Hat. Linux userspace networking, "
            "Kubernetes (SIG Autoscaling, WG Node Identity), Arch Linux on s390x, "
            "Karpenter for IBM Cloud."
        ),
        "mainEntity": {"@id": PERSON_ID},
        "breadcrumb": {
            "@type": "BreadcrumbList",
            "itemListElement": [
                {"@type": "ListItem", "position": 1, "name": "Home", "item": f"{SITE_URL}/"},
                {"@type": "ListItem", "position": 2, "name": "About", "item": f"{SITE_URL}/about/"},
            ],
        },
        "speakable": {
            "@type": "SpeakableSpecification",
            "cssSelector": ["#bio", "#now", ".faq-answer"],
        },
    }


def knows_about(ctx: dict) -> dict:
    terms = [
        _strip({
            "@type": "DefinedTerm",
            "name": t.get("name"),
            "inDefinedTermSet": t.get("url"),
        })
        for t in ctx["topics"]
    ]
    return {
        "@context": "https://schema.org",
        "@graph": [{
            "@type": "Person",
            "@id": PERSON_ID,
            "knowsAbout": terms,
        }],
    }


def projects(ctx: dict) -> dict | None:
    roles = []
    for p in ctx["projects"]:
        role: dict[str, Any] = _strip({
            "@type": "Role",
            "roleName": p.get("role"),
            "startDate": p.get("since"),
            "name": p.get("project"),
            "url": p.get("url"),
        })
        if p.get("org"):
            role["affiliation"] = {"@type": "Organization", "name": p["org"]}
        roles.append(role)
    if not roles:
        return None
    return {
        "@context": "https://schema.org",
        "@graph": [{
            "@type": "Person",
            "@id": PERSON_ID,
            "affiliation": roles,
        }],
    }


def website(_ctx: dict) -> dict:
    return {
        "@context": "https://schema.org",
        "@type": "WebSite",
        "url": f"{SITE_URL}/",
        "name": "josie.lol",
        "description": "Personal website and technical blog of Josephine Pfeiffer",
        "author": {
            "@type": "Person",
            "@id": PERSON_ID,
            "name": "Josephine Pfeiffer",
            "image": f"{SITE_URL}/me.jpg",
            "jobTitle": "Senior Software Engineer",
            "worksFor": {"@type": "Organization", "name": "Red Hat"},
            "address": {
                "@type": "PostalAddress",
                "addressLocality": "Zurich",
                "addressCountry": "Switzerland",
            },
            "email": "hi@josie.lol",
            "url": f"{SITE_URL}/",
            "mainEntityOfPage": {"@id": f"{SITE_URL}/about/"},
            "sameAs": [
                "https://github.com/pfeifferj",
                "https://gitlab.com/users/josie",
                "https://www.linkedin.com/in/josephine-pfeiffer/",
                "https://www.credly.com/users/pfeifferj",
            ],
        },
    }


def has_credential(ctx: dict) -> dict | None:
    items = []
    for c in ctx["credentials"]:
        items.append(_strip({
            "@type": "EducationalOccupationalCredential",
            "name": c.get("name"),
            "credentialCategory": "certification",
            "dateCreated": c.get("year"),
            "recognizedBy": (
                {"@type": "Organization", "name": c.get("issuer")}
                if c.get("issuer") else None
            ),
            "url": c.get("url"),
        }))
    if not items:
        return None
    return {
        "@context": "https://schema.org",
        "@graph": [{
            "@type": "Person",
            "@id": PERSON_ID,
            "hasCredential": items,
        }],
    }


def member_of(ctx: dict) -> dict | None:
    orgs = []
    for m in ctx["memberships"]:
        orgs.append(_strip({
            "@type": "Organization",
            "name": m.get("name"),
            "url": m.get("url"),
            "description": m.get("description"),
        }))
    if not orgs:
        return None
    return {
        "@context": "https://schema.org",
        "@graph": [{
            "@type": "Person",
            "@id": PERSON_ID,
            "memberOf": orgs,
        }],
    }


def published_media(ctx: dict) -> dict | None:
    items = []
    for post in ctx["blog_posts"]:
        url = post["url"] if post.get("external") else f"{SITE_URL}/blog/{post['slug']}.html"
        items.append(_strip({
            "@type": "Article",
            "headline": post.get("title"),
            "url": url,
            "datePublished": post.get("date_iso"),
            "description": post.get("description"),
            "publisher": (
                {"@type": "Organization", "name": post["publication"]}
                if post.get("publication") else None
            ),
        }))
    for pub in ctx["publications"]:
        items.append(_strip({
            "@type": pub.get("type", "Article"),
            "headline": pub.get("title"),
            "url": pub.get("url"),
            "datePublished": pub.get("datePublished"),
            "description": pub.get("description"),
            "publisher": (
                {"@type": "Organization", "name": pub["publisher"]}
                if pub.get("publisher") else None
            ),
        }))
    if not items:
        return None
    return {
        "@context": "https://schema.org",
        "@graph": [{
            "@type": "Person",
            "@id": PERSON_ID,
            "publishedMediaObject": items,
        }],
    }


def _events(talks: list[dict]) -> list[dict]:
    out: list[dict] = []
    for t in talks:
        talk_id = f"{SITE_URL}/talks/#talk-{t['slug']}"
        for idx, c in enumerate(t.get("conferences") or []):
            event: dict[str, Any] = {
                "@type": "Event",
                "@id": f"{SITE_URL}/talks/#event-{t['slug']}-{idx}",
                "name": c.get("name"),
                "startDate": c.get("date"),
                "performer": {"@id": PERSON_ID},
                "workPresented": {"@id": talk_id},
            }
            if c.get("location"):
                event["location"] = {"@type": "Place", "name": c["location"]}
            if c.get("cancelled"):
                event["eventStatus"] = "https://schema.org/EventCancelled"
            out.append({k: v for k, v in event.items() if v is not None})
    return out


def _videos(talks: list[dict]) -> list[dict]:
    out: list[dict] = []
    for t in talks:
        for idx, c in enumerate(t.get("conferences") or []):
            rec = (c.get("recording") or "").strip()
            if not rec:
                continue
            out.append(_strip({
                "@type": "VideoObject",
                "@id": f"{SITE_URL}/talks/#video-{t['slug']}-{idx}",
                "contentUrl": rec,
                "embedUrl": rec,
                "name": c.get("name"),
                "description": t.get("abstract"),
                "uploadDate": c.get("date"),
                "author": {"@id": PERSON_ID},
            }))
    return out


def _talk_works(talks: list[dict]) -> list[dict]:
    return [
        {
            "@type": "PresentationDigitalDocument",
            "@id": f"{SITE_URL}/talks/#talk-{t['slug']}",
            "name": t.get("title"),
            "description": t.get("abstract"),
            "author": {"@id": PERSON_ID},
        }
        for t in talks
    ]


def work_performed(ctx: dict) -> dict | None:
    events = _events(ctx["talks"])
    if not events:
        return None
    return {
        "@context": "https://schema.org",
        "@graph": [{
            "@type": "Person",
            "@id": PERSON_ID,
            "workPerformed": events,
        }],
    }


def talks_graph(ctx: dict) -> dict:
    return {
        "@context": "https://schema.org",
        "@graph": (
            _talk_works(ctx["talks"])
            + _events(ctx["talks"])
            + _videos(ctx["talks"])
        ),
    }


def work_history(ctx: dict) -> dict | None:
    """Person.worksFor as Role[] (employer + title + dates)."""
    roles = []
    for w in ctx["work_history"]:
        affiliation: dict[str, Any] = {
            "@type": "Organization",
            "name": w.get("employer"),
        }
        if w.get("url"):
            affiliation["url"] = w["url"]
        role = _strip({
            "@type": "Role",
            "roleName": w.get("role"),
            "startDate": w.get("start_date"),
            "endDate": w.get("end_date"),
            "affiliation": affiliation,
            "description": w.get("focus"),
        })
        roles.append(role)
    if not roles:
        return None
    return {
        "@context": "https://schema.org",
        "@graph": [{
            "@type": "Person",
            "@id": PERSON_ID,
            "worksFor": roles,
        }],
    }


def blog_posting(post: dict) -> dict:
    return _strip({
        "@context": "https://schema.org",
        "@type": "BlogPosting",
        "headline": post.get("title"),
        "description": post.get("description"),
        "author": {"@type": "Person", "name": post.get("author")},
        "datePublished": post.get("date_iso"),
        "dateModified": post.get("date_iso"),
        "publisher": {
            "@type": "Person",
            "@id": PERSON_ID,
            "name": "Josephine Pfeiffer",
            "url": f"{SITE_URL}/",
        },
        "url": post.get("canonical_url"),
        "mainEntityOfPage": {"@type": "WebPage", "@id": post.get("canonical_url")},
        "keywords": ", ".join(post.get("tags") or []) or None,
    })


def reviews(ctx: dict) -> dict | None:
    items = []
    for r in ctx["testimonials"]:
        author = _strip({
            "@type": "Person",
            "name": r.get("author"),
            "jobTitle": r.get("title"),
            "url": r.get("url"),
        })
        items.append(_strip({
            "@type": "Review",
            "@id": f"{SITE_URL}/#review-{r['slug']}",
            "itemReviewed": {"@id": PERSON_ID},
            "author": author or None,
            "datePublished": r.get("date"),
            "reviewBody": r.get("body"),
        }))
    if not items:
        return None
    return {
        "@context": "https://schema.org",
        "@graph": items,
    }


def faq(ctx: dict) -> dict | None:
    questions = [
        {
            "@type": "Question",
            "name": q["question"],
            "acceptedAnswer": {"@type": "Answer", "text": q["answer_plain"]},
        }
        for q in ctx["faq"]
    ]
    if not questions:
        return None
    return {
        "@context": "https://schema.org",
        "@type": "FAQPage",
        "@id": f"{SITE_URL}/about/#faq",
        "mainEntity": questions,
    }
