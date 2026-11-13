#!/bin/bash
# Builds the remaining scratch directories with -j 2 (a 4-way release build of swift-syntax ran out of memory).
cd "$(dirname "$0")/../Harness"
LAYOUT=single python3 ../scripts/gen.py Sources/Client class 10 construct
for spec in "6.3.3 release .build-6.3.3 x" "6.2.4 release .build-6.2.4 x" "6.4.2 debug .build-6.4.2-native native" ; do
  set -- $spec
  BS=""; [ "$4" != x ] && BS="--build-system $4"
  PATH=$HOME/swift-toolchains/$1/usr/bin:$PATH swift build -c $2 -j 2 --scratch-path $3 $BS > ../logs/setup2-$1-$2-$4.txt 2>&1
  echo "$1 $2 $4 exit=$?"
done
