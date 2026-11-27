#!/usr/bin/env python3
# Runs the real SafeDITool (MUTATE_REAL_TOOL), then applies MUTATE_PATTERN -> MUTATE_REPLACEMENT, and then
# MUTATE_PATTERN2 -> MUTATE_REPLACEMENT2, as Python regular expressions, to the generated files it wrote: those that
# declare `SafeDIOverrides`, or every one under MUTATE_ALL_FILES=1. MUTATE_KEEP names a directory that gets a copy of
# each file before the mutation. A deliberately broken build for the value harness's controls.
import json, os, re, subprocess, sys, glob, shutil
real = os.environ["MUTATE_REAL_TOOL"]
result = subprocess.run([real] + sys.argv[1:])
args = sys.argv[1:]
outputs = []
if "--swift-manifest" in args:
    manifest = json.load(open(args[args.index("--swift-manifest") + 1]))
    def walk(v):
        if isinstance(v, str) and v.endswith(".swift"): outputs.append(v)
        elif isinstance(v, dict): [walk(x) for x in v.values()]
        elif isinstance(v, list): [walk(x) for x in v]
    walk(manifest)
if "--combined-output" in args:
    outputs.append(args[args.index("--combined-output") + 1])
keep = os.environ.get("MUTATE_KEEP")
for path in outputs:
    if not os.path.exists(path): continue
    text = open(path).read()
    if "SafeDIOverrides" not in text and not os.environ.get("MUTATE_ALL_FILES"): continue
    if keep: shutil.copy(path, os.path.join(keep, str(os.getpid()) + "-" + os.path.basename(path)))
    mutated = re.sub(os.environ.get("MUTATE_PATTERN", r"__never__"), os.environ.get("MUTATE_REPLACEMENT", ""), text)
    if os.environ.get("MUTATE_PATTERN2"):
        mutated = re.sub(os.environ["MUTATE_PATTERN2"], os.environ.get("MUTATE_REPLACEMENT2", ""), mutated)
    open(path, "w").write(mutated)
sys.exit(result.returncode)
