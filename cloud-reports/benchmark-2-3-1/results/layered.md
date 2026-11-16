Machine: Intel(R) Xeon(R) Processor @ 2.10GHz, 4 CPUs, Linux-6.18.44-fc-v470-x86_64-with-glibc2.39; Swift version 6.2 (swift-6.2-RELEASE)
Load (1-minute average) at start 0.86, at end 0.98, before each shape at most 0.98
2.2.0: /home/user/safedi-2.2.0/.build/x86_64-unknown-linux-gnu/release/SafeDITool (2.2.0); main: /home/user/SafeDI/.build/x86_64-unknown-linux-gnu/release/SafeDITool (f8eeeb87); medians of 5 with min–max

| Shape | Measure | 2.2.0 | main | main / 2.2.0 |
|---|---|---|---|---|
| layered100 | generated lines | 307,315 | 137,194 | 0.45 |
| layered100 | generate wall (s) | 12.9 (12.1–12.9) | 6.599 (6.427–7.089) | 0.51 |
| layered100 | generate peak memory (MB) | 86.0 (85.4–88.2) | 225.6 (225.5–227.0) | 2.62 |
| layered100 | compile -Onone (s) | 364.5 (343.4–374.7) | 139.9 (134.1–146.1) | 0.38 |
| layered100 | compile -O (s) | 257.0 (249.9–267.1) | 127.0 (120.5–135.0) | 0.49 |
| layered100 | runtime (ns per iteration) | 534,170 (524,486–565,783) | 532,653 (494,688–609,133) | 1.00 |
| layered100 | runtime (ns per value) | 75.1 (73.7–79.5) | 74.9 (69.5–85.6) | 1.00 |
| layered100-seams | generated lines | n/a | 259,248 | n/a |
| layered100-seams | generate wall (s) | n/a | 14.0 (13.1–14.4) | n/a |
| layered100-seams | generate peak memory (MB) | n/a | 182.3 (178.7–186.4) | n/a |
| layered100-seams | compile -Onone (s) | n/a | 172.5 (167.2–177.2) | n/a |
| layered100-seams | compile -O (s) | n/a | 146.2 (144.9–149.9) | n/a |
| layered100-seams | runtime (ns per iteration) | n/a | 1,519,940 (1,346,658–1,793,152) | n/a |
| layered100-seams | runtime (ns per value) | n/a | 82.7 (73.2–97.5) | n/a |
| layered100-seams | did not build | 2.2.0: L1M0 did not compile at -Onone: /home/user/bench/fixtures-layered/layered100-seams/L1M0/File05.swift:6:30: error: type ' | | |

Where main is slower than 2.2.0 (median ratio above 1), ranked:

| Ratio | Shape | Measure |
|---|---|---|
| 2.62 | layered100 | generate peak memory (MB) |
