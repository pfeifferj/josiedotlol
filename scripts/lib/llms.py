"""Generate llms.txt and llms-full.txt from the data context."""
from __future__ import annotations

from .config import OUTPUT_ROOT, SITE_URL


def render_llms(ctx: dict) -> str:
    lines = [
        "# josie.lol",
        "",
        "> Personal website of Josephine Pfeiffer, Senior Software Engineer at "
        "Red Hat. Linux userspace networking, Kubernetes (SIG Autoscaling, WG "
        "Node Identity), Arch Linux on s390x, Karpenter for IBM Cloud.",
        "",
        ctx["person"]["bio_paragraph"],
        "",
        "## About",
        "",
        f"- [Homepage]({SITE_URL}/): bio, certifications, sameAs links",
        f"- [About]({SITE_URL}/about/): projects, affiliations, FAQ",
        "",
        "## Talks",
        "",
    ]
    for t in ctx["talks"]:
        title = t.get("title", "")
        abstract = (t.get("abstract") or "")[:200]
        lines.append(
            f"- [{title}]({SITE_URL}/talks/#talk-{t['slug']}): {abstract}"
        )
    lines.append("")
    return "\n".join(lines)


def render_llms_full(ctx: dict) -> str:
    lines = [
        "# josie.lol",
        "",
        "Personal website of Josephine Pfeiffer, Senior Software Engineer at "
        "Red Hat. Focus areas: linux userspace networking (NetworkManager), "
        "Kubernetes (SIG Autoscaling, WG Node Identity), Arch Linux on s390x, "
        "Karpenter for IBM Cloud, container security, developer productivity, "
        "internal developer platforms.",
        "",
        ctx["person"]["bio_paragraph"],
        "",
        "## About",
        "",
        "- Senior Software Engineer (rust/c) at Red Hat (Platform, GPU, Edge, and Networking). Based in Zurich / London.",
        "- Day job: Rust rewrite of NetworkManager and adjacent Linux userspace networking.",
        "- Open source: lead maintainer of Karpenter Cluster Autoscaler for IBM Cloud "
        "(adopted by Kubernetes SIG Autoscaling, Oct 2025); steering committee member, "
        "Kubernetes WG Node Identity; member, Kubernetes SIG Autoscaling (top-15 contributor, 2025); "
        "contributor to alpm.rs and paru; author of the unofficial Arch Linux s390x port.",
        "- Previously at Red Hat: Senior Infrastructure Consultant and Infrastructure Consultant "
        "(2023 to 2026) for confidential containers on OpenShift, RDMA networking for multi-node "
        "GPU inference (H100/H200, vLLM), and security reviews for financial-services and "
        "public-sector customers.",
        "- Prior to Red Hat: Technical Program Manager / Site Reliability Engineer at Sygnum Bank "
        "(2022 to 2023), preparing cloud security architecture for FINMA.",
        "- Certified Red Hat Architect (OpenShift + Enterprise Linux), Google "
        f"Cloud Architect, AWS Solutions Architect Professional. Full list at {SITE_URL}/#certs.",
        "- CVE-2023-6944 disclosed against Red Hat Developer Hub backend scaffolder plugin.",
        "",
    ]

    if ctx["projects"]:
        lines.append("## Projects")
        lines.append("")
        for p in ctx["projects"]:
            head = f"- **{p.get('project','')}** ({p.get('role','')}, since {p.get('since','')}"
            if p.get("org"):
                head += f", {p['org']}"
            head += f"): <{p.get('url','')}>"
            if p.get("description"):
                head += f". {p['description']}"
            if p.get("evidence"):
                head += f" Evidence: <{p['evidence']}>"
            lines.append(head)
        lines.append("")

    if ctx["faq"]:
        lines.append("## FAQ")
        lines.append("")
        for q in ctx["faq"]:
            lines.append(f"### {q['question']}")
            lines.append("")
            lines.append(q["answer_md"])
            lines.append("")

    lines.append("## Talks")
    lines.append("")
    for t in ctx["talks"]:
        lines.append(f"### {t.get('title','')}")
        lines.append("")
        lines.append(t.get("abstract", ""))
        lines.append("")
        if t.get("conferences"):
            lines.append("Presented at:")
            for c in t["conferences"]:
                name = c.get("name", "")
                location = c.get("location", "")
                date = c.get("date", "")
                lines.append(f"- {name} ({location}, {date})")
            lines.append("")

    return "\n".join(lines)


def write_llms(ctx: dict) -> None:
    (OUTPUT_ROOT / "llms.txt").write_text(render_llms(ctx), encoding="utf-8")
    (OUTPUT_ROOT / "llms-full.txt").write_text(render_llms_full(ctx), encoding="utf-8")
    print("rendered llms.txt + llms-full.txt")
