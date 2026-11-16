# Stack-level leak acceptance seeds (seam corpus, beyond seed 999)

Features: `generateDependencyTree`. On main 58cbc93, each seed fails "the seam build keeps alive what the inline build frees", and no corpus entry documents the leak. All are the known in-seam leak. Checked at the heads of slices 3, 4 and 7. None may remain at the stack top.

99 seeds: 1050 1094 1145 1156 1232 1269 1315 1471 1524 1541 1569 1581 1637 1668 1790 1794 2006 2056 2134 2149 2208 2277 2303 2441 2449 2464 2496 2538 2594 2645 2667 2687 2717 2735 2791 2819 2873 2881 2914 2931 2976 2985 3019 3057 3066 3082 3163 3181 3203 3256 3264 3329 3337 3383 3430 3463 3465 3479 3522 3532 3575 3661 3723 3729 3736 3855 3859 3912 3929 3937 3950 3966 3994 4054 4074 4090 4091 4184 4217 4335 4339 4435 4525 4538 4595 4627 4634 4670 4686 4717 4718 4731 4765 4772 4811 4818 4842 4891 4954

To check a head, run the fuzzer on these seeds:

    SAFEDI_GRAPH_FUZZER_FEATURES=generateDependencyTree SAFEDI_GRAPH_FUZZER_SEEDS=1050,1094,1145,1156,1232,1269,1315,1471,1524,1541,1569,1581,1637,1668,1790,1794,2006,2056,2134,2149,2208,2277,2303,2441,2449,2464,2496,2538,2594,2645,2667,2687,2717,2735,2791,2819,2873,2881,2914,2931,2976,2985,3019,3057,3066,3082,3163,3181,3203,3256,3264,3329,3337,3383,3430,3463,3465,3479,3522,3532,3575,3661,3723,3729,3736,3855,3859,3912,3929,3937,3950,3966,3994,4054,4074,4090,4091,4184,4217,4335,4339,4435,4525,4538,4595,4627,4634,4670,4686,4717,4718,4731,4765,4772,4811,4818,4842,4891,4954 SAFEDI_GRAPH_FUZZER_REPORT=report.txt \
      swift test --traits sourceBuild --filter SafeDIToolGraphFuzzerTests/longRun

A seed still leaks when its run reports a seamRetainsWhatInlineFrees failure. Beyond the corpus no entry lists these seeds, so every other failure kind they also report (builder surface, renamed order) fails the run too. Read the report for retention lines, not the exit code.
