#!/usr/bin/env python3
import json, sys
for path in sys.argv[1:]:
	print("==", path)
	for l in open(path):
		if not l.startswith("{"):
			print(l.strip()); continue
		r = json.loads(l)
		parts = [r["edit"].ljust(16), "target:" + ",".join(r["target_outputs_changed"] or ["none"]).ljust(15)]
		parts.append(f"swiftΔ {len(r['dependents_whose_swift_changed'])} safediΔ {len(r['dependents_whose_safedi_changed'])}")
		for model, v in r["models"].items():
			parts.append(f"| {model}: reruns {v['reruns_excluding_target']} wasted {v['wasted']} ({v['wasted_user_s']:.2f}s user, {v['wasted_wall_s']:.2f}s wall) all-reruns {v['rerun_user_s']:.2f}s user unsound {len(v['unsound'])}")
		parts.append(f"| per-repeat totals user {r['per_repeat_total_user_s']} wall {r['per_repeat_total_wall_s']}")
		print(" ".join(parts))
