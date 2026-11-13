#!/bin/bash
# Stands in for the macro plugin: appends everything the compiler sends to /tmp/requests.bin, then runs the
# real plugin, whose path is in plugin-path next to this script. (The compiler does not pass its environment on.)
tee -a /tmp/requests.bin | "$(cat "$(dirname "$0")/plugin-path")"
