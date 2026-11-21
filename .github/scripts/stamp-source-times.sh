#!/bin/bash
# Usage: stamp-source-times.sh
#
# Gives every file git tracks a modification time derived from its content (its blob hash), so that a file whose
# content two checkouts share has the same time in both. SwiftPM rebuilds a target when a source's modification
# time or size differs from the one it last built with, and a fresh checkout gives every file the time of the
# checkout, so without this a restored build directory rebuilds every target of this package. With it, a build
# restored from one commit rebuilds, at another commit, only the targets whose files differ, and what depends on
# them.
#
# The time is 1970-01-02 plus the first 30 bits of the blob hash in seconds, which ends in 2004: two contents of
# one path get the same time, and so might be taken for each other, only when those bits and the files' sizes are
# all equal. The nanoseconds stay zero, because SwiftPM does not compare them. A symbolic link is stamped itself,
# not its target; SwiftPM reads the target's time, which is stamped as its own file. Files git does not track
# keep their times.
#
# Measured in debug on Linux (Swift 6.2): a build directory restored into a fresh clone of the same commit, at the
# same path, rebuilt in 12 seconds what took 419 from nothing (the six files of the SafeDI module and the test
# discovery); a change to a file symbolic links name rebuilt the targets that hold the links; a change to one
# file's nanoseconds alone rebuilt nothing. In release on CI, "Build Tests" of verify.yml took about 10 seconds from
# a build of the same commit (run 43762598351), about 2 minutes after a change to one test file (43763818802), and
# 12 minutes from nothing (43761135608).
#
# Run it from anywhere in the checkout, after checkout and before the build, in every job whose build directory
# is saved for, or restored from, another commit.
set -euo pipefail
# Separate statements, so that a failing git stops the script: a job that stamped nothing would save, with a green
# check, a build every later run rebuilds whole.
top_level=$(git rev-parse --show-toplevel)
cd "$top_level"
# GNU's `touch` reads a time in seconds since 1970 (`-d @seconds`). macOS's does not, so there the time is spelled
# out, in UTC, by its `date`, which reads seconds with `-r`.
entries=$(mktemp)
trap 'rm -f "$entries"' EXIT
if touch -d @86400 -- "$entries" 2>/dev/null; then
  touch_reads_seconds=true
else
  touch_reads_seconds=false
fi
git ls-files --stage -z > "$entries"
count=0
while IFS= read -r -d '' entry; do
  # <mode> <blob hash> <stage>\t<path>
  metadata=${entry%%$'\t'*}
  path=${entry#*$'\t'}
  hash=${metadata#* }
  hash=${hash%% *}
  # A submodule's entry is a commit, not a file, and a path the index holds but the checkout lacks has no time.
  if [[ ${metadata%% *} == 160000 || ! ( -e $path || -L $path ) ]]; then
    continue
  fi
  seconds=$((86400 + (16#${hash:0:8} >> 2)))
  if [[ $touch_reads_seconds == true ]]; then
    touch -h -d "@$seconds" -- "$path"
  else
    TZ=UTC touch -h -t "$(TZ=UTC date -r "$seconds" +%Y%m%d%H%M.%S)" -- "$path"
  fi
  count=$((count + 1))
done < "$entries"
if (( count == 0 )); then
  echo "No tracked file was found to stamp." >&2
  exit 1
fi
echo "Stamped $count files with times derived from their content."
