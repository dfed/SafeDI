#!/bin/bash
# prof.sh NAME COMMANDS_FILE LINE: perf-record that generate command, write NAME.self.txt and NAME.incl.txt
set -e
name=$1; cmd=$(sed -n "${3}p" "$2")
cd /home/user/audit
perf record -o prof/$name.data -e cpu-clock -F 400 --call-graph dwarf,32768 -- bash -c "$cmd" >/dev/null 2>prof/$name.rec.txt
perf report -i prof/$name.data --no-children --stdio --percent-limit 0.7 -g none 2>/dev/null | grep -v "^#" | grep -v "^$" | head -40 > prof/$name.self.txt
perf report -i prof/$name.data --children --stdio --percent-limit 2 -g none 2>/dev/null | grep -v "^#" | grep -v "^$" | head -120 > prof/$name.incl.txt
