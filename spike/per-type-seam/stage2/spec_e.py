"""Writes shape E's spec (synthetic growth shape) for N screens. Usage: python3 -I spec_e.py N > spec.json"""
import json
import sys

n = int(sys.argv[1])
layers = n // 4
types = {"Home": {"properties": [[f"screen{k}Builder", "inst", f"Screen{k}"] for k in range(4)]}}
for i in range(n):
    layer = i // 4
    children = [] if layer == layers - 1 else [(layer + 1) * 4 + k for k in range(4) if k != i % 4]
    types[f"Screen{i}"] = {"forwarded": ["id"], "receives": ["service"], "properties": [[f"model{i}", "const", f"Model{i}"]] + [[f"screen{c}Builder", "inst", f"Screen{c}"] for c in children]}
    types[f"Model{i}"] = {"receives": ["id", "service"], "properties": [["api", "hole", "Api"]] if layer == layers - 1 else []}
json.dump({"seam": "Home", "types": types, "holes": {"Api": "LiveApi"}, "fill_receives": {"LiveApi": ["id", "service"]}, "pass_through": ["service"], "root_declares": [["service", "Service"]]}, sys.stdout, indent=1)
