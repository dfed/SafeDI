#!/bin/bash
# scale.sh N SEED — generates #646's mock graph with main's tool, rewrites it into the shared form, and prints lines,
# generate time, and functions. Work files go to SCALE_DIR (default ~/.cache/n2-scale).
set -euo pipefail
n=$1; seed=$2; here=$(cd "$(dirname "$0")" && pwd)
work=${SCALE_DIR:-$HOME/.cache/n2-scale}/s$n-$seed; mkdir -p "$work"
python3 "$here/../F5_gen.py" "$n" "$seed" >/dev/null
cp "$here/s$n-$seed/shared/App/Types.swift.txt" "$work/Types.swift"
printf "%s" "$work/Types.swift" > "$work/files.csv"
/usr/bin/time -f "%e %M" -o "$work/generate.time" /home/user/SafeDI/.build/debug/SafeDITool generate "$work/files.csv" --combined-output "$work/today.swift" --module-name App
python3 "$here/shared_form.py" "$work/today.swift" "$work/shared.swift" "$work/stats.json"
python3 - "$work" "$n" "$seed" <<'PY'
import json, sys
work, n, seed = sys.argv[1:]
stats = json.load(open(f"{work}/stats.json"))
seconds, kilobytes = open(f"{work}/generate.time").read().split()
today = sum(1 for _ in open(f"{work}/today.swift")); shared = sum(1 for _ in open(f"{work}/shared.swift"))
print(json.dumps({"screens": int(n), "seed": int(seed), "todayLines": today, "sharedLines": shared,
                  "debugGenerateSeconds": float(seconds), "functions": sum(s["functions"] for s in stats),
                  "rootMockFunctions": stats[0]["functions"] if stats else None, "fixedPaths": sum(s["fixed_paths"] for s in stats)}))
PY
