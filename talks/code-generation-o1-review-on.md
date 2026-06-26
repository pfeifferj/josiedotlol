---
title: "Code Generation is O(1), Code Review is O(n)"
date: 2026-08-15
abstract: AI didn't make software cheaper. It moved the cost from writing code to understanding it, and dumped that bill on maintainers who never agreed to pay it. This talk names the mechanism: generation is O(1) for the contributor, comprehension is O(n) for the maintainer. Every symptom we're complaining about in 2026, the PR firehose, the slop, reviewer burnout, is the same asymmetry wearing different hats.
conferences:
  - name: FrOSCon
    location: Sankt Augustin
    date: 2026-08-15
---

For decades the bottleneck in open source was writing the code. Agentic tooling collapsed that cost to near zero, and quietly relocated it. The work didn't vanish; it migrated downstream to reviews, where understanding a confidently-wrong 600-line PR now costs more than writing it would have.

This talk names the mechanism: generation is O(1) for the contributor, comprehension is O(n) for the maintainer. Every symptom we're complaining about in 2026, the PR firehose, the slop, reviewer burnout, the eerie sense that contribution got easier while maintaining got worse, is the same asymmetry wearing different hats.

I maintain projects that now receive PRs written by people who didn't read the code they submitted. I'll walk through real examples (the good, the cursed, the load-bearing misunderstanding) and show why our entire governance vocabulary, DCO, review, reputation, "looks good to me", was built for a world where authoring something was evidence you understood it. That evidence is now gone.

This is the diagnostic half. I argue the asymmetric-effort problem is the root cause beneath most AI-and-FOSS anxiety, that pretending it's a tooling problem or a "just review harder" problem will burn out a generation of maintainers, and that the fix has to be structural, not moral. You'll leave with a sharper way to think about every governance decision: who's paying the comprehension tax, and is that fair?
