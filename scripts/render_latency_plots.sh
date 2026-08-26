#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS="${ROOT}/benchmark-results"
OUTPUT="${ROOT}/docs/benchmarks"

mkdir -p "${OUTPUT}"

for csv in "${RESULTS}"/*/latency.csv; do
    run_dir="$(dirname "${csv}")"
    run_id="$(basename "${run_dir}")"

    echo "Rendering ${run_id}"

    tmp="$(mktemp -d)"
    trap 'rm -rf "${tmp}"' EXIT

    mkdir -p "${tmp}/data"
    cp "${csv}" "${tmp}/data/latency.csv"
    cp "${ROOT}/analysis.ipynb" "${tmp}/analysis.ipynb"

    python3 - "${tmp}/analysis.ipynb" <<'PY'
import json
import sys

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as f:
    nb = json.load(f)

for cell in nb["cells"]:
    if cell["cell_type"] != "code":
        continue

    src = "".join(cell["source"])

    if "from bokeh.io import" in src:
        src = src.replace(
            "from bokeh.io import output_notebook, show",
            "from bokeh.io import output_notebook, show, export_png",
        )

    src = src.replace(
        "show(p)",
        'export_png(p, filename="distribution.png")',
    )

    src = src.replace(
        "show(q)",
        'export_png(q, filename="tail.png")',
    )

    cell["source"] = src.splitlines(keepends=True)

with open(path, "w", encoding="utf-8") as f:
    json.dump(nb, f)
PY

    (
        cd "${tmp}"
        jupyter nbconvert \
            --to notebook \
            --execute \
            --inplace \
            analysis.ipynb
    )

    mv "${tmp}/distribution.png" \
       "${OUTPUT}/${run_id}-distribution.png"

    mv "${tmp}/tail.png" \
       "${OUTPUT}/${run_id}-tail.png"

    rm -rf "${tmp}"
    trap - EXIT
done