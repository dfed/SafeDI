#!/bin/zsh
# Reruns every N2 fixture from the committed files: F1–F3 regenerate today's mock with the checkout's SafeDITool (`b`,
# `p`), F4 and every shared form (`s`, `u`) are hand-written or written by F5/shared_form.py. Summaries go to
# <fixture>/results/summary.txt; measure.sh writes the compile and runtime figures.
set -uo pipefail
here=${0:A:h}; cd $here
python3 F1_gen.py; python3 F23_gen.py; python3 F23_shared.py
for f in F1 F2 F3; do echo "== $f"; ./run-fixture.zsh $f b s p | tee $f/results/summary.txt; done
echo "== F4"; ./run-fixture.zsh F4 a c2 h s | tee F4/results/summary.txt
# F5: today's file is committed (generate takes minutes and its compile 13 GB); the shared forms are rewritten from it.
python3 F5_gen.py 12 5 >/dev/null
(cd F5/s12-5 && python3 ../shared_form.py b/stored/App.swift.txt s/App/Generated/App.swift stats.json \
	&& python3 ../shared_form.py b/stored/App.swift.txt u/App/Generated/App.swift stats-uniform.json --uniform \
	&& python3 ../shared_form.py b/stored/App.swift.txt l/App/Generated/App.swift stats-loop.json --loop \
	&& python3 ../shared_form.py b/stored/App.swift.txt lb/App/Generated/App.swift stats-loop.json --loop --boxed \
	&& python3 ../driver_gen.py b/stored/App.swift.txt 12 3 b/App/Sources/Driver.swift.txt shared/App/Types.swift.txt \
	&& cp b/App/Sources/Driver.swift.txt s/App/Sources/ && cp b/App/Sources/Driver.swift.txt u/App/Sources/ \
	&& cp b/App/Sources/Driver.swift.txt l/App/Sources/ && cp b/App/Sources/Driver.swift.txt lb/App/Sources/)
echo "== F5"; SKIP_GENERATE=1 ./run-fixture.zsh F5/s12-5 b s u l lb | tee F5/s12-5/results/summary.txt
