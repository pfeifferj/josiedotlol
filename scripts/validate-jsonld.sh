#!/usr/bin/env bash
set -euo pipefail

shopt -s nullglob

targets=("index.html")
for f in blog/*.html talks/*.html about/*.html; do
    [[ "$f" == *template.html ]] && continue
    targets+=("$f")
done

python3 - "${targets[@]}" <<'PY'
import sys, re, json, pathlib

exit_code = 0
for path in sys.argv[1:]:
    text = pathlib.Path(path).read_text(encoding="utf-8")
    blocks = re.findall(
        r'<script[^>]*type=[\'"]application/ld\+json[\'"][^>]*>(.*?)</script>',
        text, re.DOTALL,
    )
    for i, block in enumerate(blocks, 1):
        try:
            obj = json.loads(block)
        except json.JSONDecodeError as e:
            print(f"{path}: block #{i} parse error: {e}")
            exit_code = 1
            continue
        if not isinstance(obj, dict):
            print(f"{path}: block #{i} not a JSON object")
            exit_code = 1
            continue
        if "@context" not in obj:
            print(f"{path}: block #{i} missing @context")
            exit_code = 1
        if "@type" not in obj and "@graph" not in obj:
            print(f"{path}: block #{i} missing @type and @graph")
            exit_code = 1

sys.exit(exit_code)
PY
