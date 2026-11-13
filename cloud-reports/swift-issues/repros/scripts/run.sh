#!/bin/bash
# run.sh TOOLCHAIN CONFIG(debug|release) BUILDSYSTEM(default|native|swiftbuild) LABEL
# Env: CLEAN=0 skips cleaning; TOUCH=File.swift touches Sources/Client/File.swift first (incremental build).
# Cleans the Client module, builds it, writes the macro log to logs/LABEL.log.
set -e
HERE=$(cd "$(dirname "$0")/.." && pwd)
TC=$1 CONFIG=$2 BS=$3 LABEL=$4
export PATH=$HOME/swift-toolchains/$TC/usr/bin:$PATH
cd "$HERE/Harness"
SCRATCH=.build-$TC
[ "$BS" != default ] && SCRATCH=$SCRATCH-$BS && BSFLAG="--build-system $BS"
# Swift Build (6.4's default) rebuilds swift-syntax when Debug and Release share a scratch directory,
# and a 4-way Release build of swift-syntax runs this 16 GB machine out of memory.
[ "$CONFIG" = release ] && JOBS="-j 2"
[ "$CONFIG" = release ] && [ "$TC" = 6.4.2 ] && [ "$BS" = default ] && SCRATCH=$SCRATCH-release
[ -n "$TOUCH" ] && sleep 1 && touch Sources/Client/$TOUCH
if [ "${CLEAN:-1}" = 1 ]; then
  # Swift Build: delete the target's intermediates. Native: delete compiled outputs only (it needs its output file map).
  find $SCRATCH -name 'Client-t.build' -type d -prune -exec rm -rf {} + 2>/dev/null
  find $SCRATCH -path '*/checkouts' -prune -o -path '*Client.build/*' -type f ! -name 'output-file-map.json' ! -name 'sources' ! -name '*.modulemap' ! -name '*.resp' -print | xargs rm -f
  find $SCRATCH -path '*/checkouts' -prune -o \( -name 'Client.swiftmodule' -o -name 'Client.o' -o -name 'Client.swiftdoc' -o -name 'Client.swiftsourceinfo' \) -print | xargs rm -rf
fi
true
mkdir -p "$HERE/logs"
LOG="$HERE/logs/$LABEL.log"; rm -f "$LOG" /tmp/noop-macro.log
start=$(date +%s.%N)
swift build -c $CONFIG --scratch-path $SCRATCH $BSFLAG --target Client $JOBS ${EXTRA} > "$HERE/logs/$LABEL.build.txt" 2>&1 || { tail -20 "$HERE/logs/$LABEL.build.txt"; exit 1; }
end=$(date +%s.%N)
mv /tmp/noop-macro.log "$LOG" 2>/dev/null || touch "$LOG"
echo "$LABEL build_seconds=$(echo "$end - $start" | bc)" >> "$HERE/logs/$LABEL.build.txt"
