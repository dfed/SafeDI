#!/usr/bin/env python3
"""frames.py FILE [--show]: prints the size of each message the compiler sent and of its staticBuildConfiguration."""
import json, struct, sys
data = open(sys.argv[1], "rb").read(); offset = 0; rows = []
while offset + 8 <= len(data):
    (count,) = struct.unpack_from("<Q", data, offset); offset += 8
    if count == 0: continue
    message = json.loads(data[offset:offset + count]); offset += count
    kind = next(iter(message))
    configuration = (message[kind] or {}).get("staticBuildConfiguration") or ""
    rows.append((kind, count, len(configuration.encode())))
expansions = [r for r in rows if r[0].startswith("expand")]
for kind in sorted({r[0] for r in rows}):
    print(f"{kind}: {sum(1 for r in rows if r[0] == kind)} messages")
if expansions:
    print(f"expansion requests: {len(expansions)}, bytes each: {min(r[1] for r in expansions)}-{max(r[1] for r in expansions)}, "
          f"staticBuildConfiguration bytes each: {min(r[2] for r in expansions)}-{max(r[2] for r in expansions)}, "
          f"total: {sum(r[1] for r in expansions)} bytes")
if len(sys.argv) > 2 and sys.argv[2] == "--show":
    # Field-by-field size of the first request's staticBuildConfiguration.
    offset = 0
    while offset + 8 <= len(data):
        (count,) = struct.unpack_from("<Q", data, offset); offset += 8
        message = json.loads(data[offset:offset + count]) if count else {}; offset += count
        configuration = message.get("expandAttachedMacro", {}).get("staticBuildConfiguration")
        if configuration:
            for key, value in json.loads(configuration).items():
                print(f"  {key}: {len(json.dumps(value))} bytes" + (f", {len(value)} entries" if isinstance(value, list) else f" = {json.dumps(value)}"))
            break
