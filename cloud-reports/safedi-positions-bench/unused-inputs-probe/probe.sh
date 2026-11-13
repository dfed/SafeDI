#!/bin/sh
# probe.sh USED UNUSED OUT UNUSED_LIST
echo RAN >&2
cat "$1" > "$3"
echo "$2" > "$4"
