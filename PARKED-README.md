# Parked: build each seam's tree once, step 1

This branch is parked; do not merge it and do not delete it.

**What it does.** Emission reuses the generator that a seam's settling signature pass built, instead of building the tree a
third time. A module that generates no roots no longer builds the seam world's scope map. Generated code is byte-identical.

**Why parked.** On E6d-1200, wall and CPU drop about 6% (3.32 s to 3.12 s). Peak live heap, measured with the peakheap
shim, rises 10% on E6d-600 (44.6 to 49.3 MB) and 15% on N5i-10 (11.4 to 13.1 MB), against a 3% gate.

**Open question, unexplained.** heaptrack on E6d-600's Feature module puts both peaks in emission, with all 1,800 code
tasks alive at once. With reuse, each code task's async frames take 11.7 KB, against 9.9 KB when emission builds the tree
afresh (21.1 against 17.9 MB in all). The cause was not found. The kept trees also hold a little more than fresh ones,
including the SeamRoot of the pass before the settling one. A probe that keeps the settled trees but builds emission's
afresh measures the same 49 MB.

Full figures: the project's `designs/seam-tree-once/step1-measurements.md`.
