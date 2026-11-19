#!/bin/bash
# make_fixtures.sh OUT: writes the benchmark's shapes as OUT/<shape>/<Module>/*.swift plus OUT/<shape>/modules.txt
# ("Module dep,dep" per line, in build order). Generators: make_screens.py (issue #646's), n1.py (N1, E6d), n5.py (N5).
set -e
here=$(cd "$(dirname "$0")" && pwd); out=$1; mkdir -p $out
for spec in "issue646-12 12 1" "issue646-16 16 1" "issue646-mock-12 12 5 mock"; do
  set -- $spec; python3 -I $here/make_screens.py $out/$1/App $2 $3 $4; echo "App " > $out/$1/modules.txt
done
for n in 40 200; do python3 -I $here/n1.py $out/N1-$n n1 $n seam; done
# E6d: N independent seams, each with a leaf and an `any Api` hole App fills; -inline is the same graph as a 2.2.0
# user writes it, without seams.
for n in 600 1200; do python3 -I $here/n1.py $out/E6d-$n e6d $n seam; python3 -I $here/n1.py $out/E6d-$n-inline e6d $n inline2; done
for l in 8 10; do
  python3 -I $here/n5.py $out/N5i-$l.tmp $l
  python3 -I $here/n5.py $out/N5inline-$l.tmp $l --inline
done
for t in $out/*.tmp; do
  d=${t%.tmp}; mkdir -p $d; : > $d/modules.txt
  for m in $(cat $t/modules.txt); do
    mkdir -p $d/$m; cp $t/$m/Sources/*.swift $d/$m/
    deps=$( [ -f $t/$m/dependencies.txt ] && grep -v '^$' $t/$m/dependencies.txt | paste -sd, || true)
    echo "$m $deps" >> $d/modules.txt
  done
  rm -rf $t
done
