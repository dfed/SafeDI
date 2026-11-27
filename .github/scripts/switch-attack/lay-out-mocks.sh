#!/bin/bash
# lay-out-mocks.sh CHECKOUT
# Turns on mock layout from node records in CHECKOUT's SafeDITool sources, for the mock on/off gate. The tool never reads
# SAFEDI_NODE_RECORDS_LAY_OUT_MOCKS (only test support does), so a built tool lays out only with these two edits:
# `laysOutMockRoots` defaults to `true`, and mock generation takes the node-record path when it is set, as when a test
# observes records. Each edit finds its line by pattern, not by position, so it applies to any head of the mock kinds
# integration whatever moved around it, and fails, naming the file, when its line is gone or appears twice.
set -u
root=$1
edit() {
  local file=$root/$1 pattern=$2 replacement=$3 count
  count=$(grep -cE "$pattern" "$file")
  if [ "$count" != 1 ]; then echo "lay-out-mocks.sh: $1 has $count lines matching $pattern, not one" >&2; exit 1; fi
  sed -E -i "s/$pattern/$replacement/" "$file"
}
edit Sources/SafeDICore/Generators/NodeRecords/NodeRecordsObservation.swift \
  '(@TaskLocal public static var laysOutMockRoots) = false$' '\1 = true'
edit Sources/SafeDICore/Generators/DependencyTreeGenerator+MockOrchestration.swift \
  'guard NodeRecordsObservation\.observer != nil else \{' 'guard NodeRecordsObservation.observer != nil || NodeRecordsObservation.laysOutMockRoots else {'
git -C "$root" diff --stat
