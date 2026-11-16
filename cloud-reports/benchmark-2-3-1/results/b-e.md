Machine: Intel(R) Xeon(R) Processor @ 2.10GHz, 4 CPUs, Linux-6.18.44-fc-v470-x86_64-with-glibc2.39; Swift version 6.2 (swift-6.2-RELEASE)
Load (1-minute average) at start 1.00, at end 1.19, before each shape at most 1.24
main: /home/user/SafeDI/.build/x86_64-unknown-linux-gnu/release/SafeDITool (03a6874d); slice2: /home/user/safedi-s2/.build/x86_64-unknown-linux-gnu/release/SafeDITool (8dae4da1); medians of 3 with min–max

| Shape | Measure | main | slice2 | slice2 / main |
|---|---|---|---|---|
| E8-seam | generated lines | 530 | 699 | 1.32 |
| E8-seam | generate wall (s) | 0.121 (0.120–0.125) | 0.125 (0.122–0.131) | 1.04 |
| E8-seam | generate peak memory (MB) | 39.4 (39.2–39.4) | 39.4 (39.4–39.9) | 1.00 |
| E16-seam | generated lines | 2,410 | 2,699 | 1.12 |
| E16-seam | generate wall (s) | 0.541 (0.485–0.557) | 0.610 (0.552–0.682) | 1.13 |
| E16-seam | generate peak memory (MB) | 62.1 (62.0–62.6) | 62.7 (62.3–63.5) | 1.01 |
| E24-seam | generated lines | 17,346 | 17,755 | 1.02 |
| E24-seam | generate wall (s) | 8.635 (8.456–8.851) | 8.598 (8.591–10.105) | 1.00 |
| E24-seam | generate peak memory (MB) | 361.1 (361.0–366.3) | 364.5 (364.1–365.6) | 1.01 |

Where slice2 is slower than main (median ratio above 1), ranked:

| Ratio | Shape | Measure |
|---|---|---|
| 1.13 | E16-seam | generate wall (s) |
| 1.04 | E8-seam | generate wall (s) |
| 1.01 | E16-seam | generate peak memory (MB) |
| 1.01 | E24-seam | generate peak memory (MB) |
| 1.00 | E8-seam | generate peak memory (MB) |
