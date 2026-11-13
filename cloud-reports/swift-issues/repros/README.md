# Reproduction projects

None of these use SafeDI. Each builds with swift-syntax 604.0.0. The Swift sources here were reformatted with this repository's SwiftFormat configuration (tabs), and after that each package was built again on Linux and reproduced the same counts.

- **`MacroRepro/`** is the package the issue drafts inline: `@NoopPeer` and `@NoopMember` expand to nothing, and the plugin appends one line per expansion to `/tmp/expansions.log`, naming the frontend job that asked. On Linux it reads the job from `/proc`. On macOS it logs only the frontend's process ID, and SwiftPM's macro sandbox will probably need `--disable-sandbox`; that's untested. `generate.sh N` scales the client to N types.
  - `request-sizes/` records what the compiler sends a plugin. Write the built plugin's path to `request-sizes/plugin-path`, then run `swiftc -typecheck Client.swift -load-plugin-executable ./record-plugin.sh#NoopMacrosPlugin` and `python3 frames.py /tmp/requests.bin --show`.
- **`RuleCheck/`** shows that a peer or member macro declaring no `names:` cannot add a stored property. The build fails on purpose, with "declaration name … is not covered by macro".
- **`Harness/`** is the measurement harness behind the numbers in `../results`:
  - its plugin logs every expansion with the frontend job (reading `-primary-file`, `-primary-filelist` and response files from `/proc`), the plugin's cumulative CPU time, and each request's size and `staticBuildConfiguration` size;
  - when `/tmp/noop-macro-drop-configuration` exists, it hands swift-syntax each request without that field;
  - when `/tmp/noop-macro-samples/` exists, it saves sample requests there.

  The log goes to `/tmp/noop-macro.log`, because Swift Build and the frontend don't pass environment variables to the plugin. `Sources/DecodeBench` times swift-syntax's decoding of a captured request. `Sources/Client` holds a small generated client; the scripts regenerate it.
- **`scripts/`**:
  - `gen.py DIR KIND N USE [MACROS]` writes the client: with `LAYOUT=single`, all types in `Types.swift`; otherwise one type per file.
  - `run.sh TOOLCHAIN CONFIG BUILDSYSTEM LABEL` cleans the `Client` module (or, with `CLEAN=0 TOUCH=File.swift`, touches a file), builds it, and moves the log to `logs/LABEL.log`. It expects toolchains in `~/swift-toolchains/<version>`, unpacked from swift.org's tarballs.
  - `matrix.sh` runs the scale matrix.
  - `setup-rest.sh` pre-builds scratch directories with `-j 2`; a 4-way Release build of swift-syntax ran a 16 GB machine out of memory.
  - `summarize.py` and `table.py` print the counts.
