# Every macro expansion request carries the full static build configuration (about 4 KB), and swift-syntax decodes it for each request

## Description

Since Swift 6.3, every `expandAttachedMacro` request the compiler sends to a macro plugin includes a `staticBuildConfiguration` field. It's a JSON string of about 4–4.5 KB that lists every feature, attribute, custom condition and target property. With swift-syntax 604, `PluginProviderMessageHandler.handleMessage` decodes that string into a `StaticBuildConfiguration` for every request. It does so before running the macro, whether or not the macro reads `context.buildConfiguration`. The configuration content is the same for every request a plugin process receives. The decode multiplies the plugin's per-request message-decoding cost about tenfold: 7.7 µs → 100 µs with swift-syntax built for Release, 87 µs → 845 µs built for Debug. In a measured Debug build of 1,000 macro-using types, the plugin's CPU time went from 8.6 s with 6.2.4 to 15.6 s with 6.4.2, for the same number of expansions.

## Environment

- Swift 6.4.2 (swift-6.4.2-RELEASE), 6.3.3 and 6.2.4, release toolchains from swift.org.
- Ubuntu 24.04.5 LTS, x86_64, 4 cores, 16 GB.
- swift-syntax 604.0.0.
- SwiftPM's default build system on each: Swift Build on 6.4.2, native on 6.3.3 and 6.2.4.
- Not tested: macOS or Xcode.

## Steps to reproduce

This records the messages the compiler sends to a plugin without changing the plugin. Use any macro plugin built with swift-syntax 604, for example `NoopMacrosPlugin` from the related report about peer macros. Its `NoopPeerMacro` returns `[]`.

1. Build the plugin and write its path next to the recording script:

   ```bash
   swift build && echo "$(swift build --show-bin-path)/NoopMacrosPlugin" > request-sizes/plugin-path
   ```

2. `request-sizes/record-plugin.sh` (`chmod +x`). The frontend doesn't pass its environment to the plugin process, so the plugin path comes from a file:

   ```bash
   #!/bin/bash
   # Stands in for the macro plugin: appends everything the compiler sends to /tmp/requests.bin, then runs the
   # real plugin, whose path is in plugin-path next to this script. (The compiler does not pass its environment on.)
   tee -a /tmp/requests.bin | "$(cat "$(dirname "$0")/plugin-path")"
   ```

3. `request-sizes/Client.swift`:

   ```swift
   @attached(peer)
   macro NoopPeer() = #externalMacro(module: "NoopMacrosPlugin", type: "NoopPeerMacro")

   struct S {
   	@NoopPeer var a: Int = 0
   }
   ```

4. `request-sizes/frames.py` reads the recorded frames (an 8-byte little-endian length, then JSON):

   ```python
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
   ```

5. With each compiler, and the same plugin binary:

   ```bash
   cd request-sizes && rm -f /tmp/requests.bin && swiftc -typecheck Client.swift -load-plugin-executable ./record-plugin.sh#NoopMacrosPlugin && python3 frames.py /tmp/requests.bin --show
   ```

## Expected result

Requests stay about the size of the syntax they carry, as with 6.2. Alternatively, the build configuration is sent once per plugin process, for example with the capability exchange, or only to plugins or macros that ask for it. And swift-syntax decodes it at most once per process, or only when a macro reads `context.buildConfiguration`.

## Actual result

One request for a one-line declaration, with each compiler and the same plugin binary:

| Compiler | Request bytes | `staticBuildConfiguration` bytes |
|---|---|---|
| 6.2.4 | 670 | (absent) |
| 6.3.3 | 4,715 | 3,651 |
| 6.4.2 | 5,143 | 4,043 |

The configuration in the 6.4.2 request (`--show`):

```
  attributes: 946 bytes, 64 entries
  compilerVersion: 25 bytes = {"components": [6, 4, 2]}
  customConditions: 2 bytes, 0 entries
  endianness: 8 bytes = "little"
  features: 2849 bytes, 113 entries
  languageMode: 23 bytes = {"components": [5, 10]}
  targetArchitectures: 10 bytes, 1 entries
  targetAtomicBitWidths: 20 bytes, 5 entries
  targetEnvironments: 2 bytes, 0 entries
  targetOSs: 9 bytes, 1 entries
  targetObjectFileFormats: 7 bytes, 1 entries
  targetPointerAuthenticationSchemes: 9 bytes, 1 entries
  targetPointerBitWidth: 2 bytes = 64
  targetRuntimes: 29 bytes, 2 entries
```

In SwiftPM builds the configuration is slightly larger: 4,504 bytes in a 6.4.2 Debug build and 4,080 bytes with 6.3.3. Every expansion request in a build carries it, about 5.9 KB per request on 6.4.2 against about 900 bytes on 6.2.4. Two requests captured from the same plugin process held the same configuration, but with the elements of `features`, `attributes` and `customConditions` in a different order.

**What decoding it costs.** I timed swift-syntax 604's decoder on a captured 6.4.2 request (5,843 bytes, 4,504 of them configuration), 20,000 iterations each, or 2,000 for Debug. The two decodes `handleMessage` performs are the request itself, then `JSON.decode(StaticBuildConfiguration.self, …)` on the embedded string. The rightmost column is that request with the field removed, for comparison.

| swift-syntax built for | Decode the request | Decode the configuration string | Total per request | Request without the field |
|---|---|---|---|---|
| Release | 27.8 µs | 72.0 µs | ~100 µs | 7.7 µs |
| Debug | 502 µs | 343 µs | ~845 µs | 87 µs |

**What it costs in a build.** Here, SwiftPM's Debug build compiles the macro plugin and swift-syntax in Debug as well. I measured a clean Debug build with SwiftPM of 1,000 classes in one file, each with one member macro and two peer macros, constructed from a second file: 9,000 expansions, 3 frontend jobs. The plugin's CPU time is summed over its processes. Swift-syntax's handler only decodes the configuration when the request contains it, so I compared the same plugin binary handing the handler each request as received ("kept") with handing it the request with the field removed ("removed"). Mean of three alternating runs:

| Compiler | Plugin CPU, kept | Plugin CPU, removed | Build wall-clock, kept | Build wall-clock, removed |
|---|---|---|---|---|
| 6.4.2 | 15.3 s | 11.1 s | 15.9 s | 14.3 s |
| 6.3.3 | 14.7 s | 10.9 s | 14.5 s | 13.1 s |

Removing the field before swift-syntax sees it still leaves the cost of scanning and copying the 4.5 KB string out of each request. Across compilers, with one type per file and the same plugin source (scale table in the related report on three expansions per Debug build), the plugin used this much CPU in total for the same 8,931 Debug or 3,000 Release expansions:

| | 6.2.4 | 6.3.3 | 6.4.2 |
|---|---|---|---|
| Clean Debug build, 1,000 types | 8.6 s | 15.0 s | 15.6 s |
| Clean Release build, 1,000 types | 0.39 s | 0.76 s | 0.78 s |

The plugin reported protocol version 7 instead of 8 in its capability reply on 6.4.2, and the compiler still sent the configuration.

## Why it matters

The cost is per expansion request, so it grows with the number of macro uses multiplied by the number of frontend jobs that expand each one; Debug builds expand each attached macro about three times. In the measured 1,000-type Debug build, the requests totaled 53 MB on 6.4.2 against 8 MB on 6.2.4. Removing only swift-syntax's decode saved 4.2 s of plugin CPU and 1.6 s of wall-clock time on 4 cores. Between 6.2.4 and 6.4.2, plugin CPU for the same expansions grew by 7 s, consistent with the ~0.76 ms of extra per-request decoding measured above for Debug-built swift-syntax.

What I could not confirm: the compiler-side cost of building and serializing the configuration for each request (I measured only the plugin side), and whether Xcode builds plugins in Debug for Debug builds as SwiftPM does here. The decode happens in swift-syntax (`Sources/SwiftCompilerPluginMessageHandling/CompilerPluginMessageHandler.swift`, the `.expandFreestandingMacro` and `.expandAttachedMacro` cases of `handleMessage`), so part of a fix may belong in swift-syntax.
