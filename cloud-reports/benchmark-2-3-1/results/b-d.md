Machine: Intel(R) Xeon(R) Processor @ 2.10GHz, 4 CPUs, Linux-6.18.44-fc-v470-x86_64-with-glibc2.39; Swift version 6.2 (swift-6.2-RELEASE)
Load (1-minute average) at start 1.30, at end 1.00, before each shape at most 1.30
main: /home/user/SafeDI/.build/x86_64-unknown-linux-gnu/release/SafeDITool (03a6874d); slice2: /home/user/safedi-s2/.build/x86_64-unknown-linux-gnu/release/SafeDITool (8dae4da1); medians of 3 with min–max

| Shape | Measure | main | slice2 | slice2 / main |
|---|---|---|---|---|
| D8 | generated lines | 693 | 693 | 1.00 |
| D8 | generate wall (s) | 0.302 (0.299–0.311) | 0.294 (0.290–0.295) | 0.97 |
| D8 | generate peak memory (MB) | 37.7 (37.3–37.8) | 37.9 (37.9–38.1) | 1.00 |
| D8 | compile -Onone (s) | 1.427 (1.388–1.490) | 1.381 (1.375–1.430) | 0.97 |
| D8 | compile -O (s) | 1.517 (1.487–1.548) | 1.562 (1.484–1.695) | 1.03 |
| D12 | generated lines | 1,317 | 1,317 | 1.00 |
| D12 | generate wall (s) | 0.402 (0.399–0.407) | 0.433 (0.397–0.438) | 1.08 |
| D12 | generate peak memory (MB) | 38.3 (38.2–38.4) | 38.9 (38.6–39.1) | 1.02 |
| D12 | compile -Onone (s) | 2.373 (2.044–2.377) | 2.306 (2.258–2.323) | 0.97 |
| D12 | compile -O (s) | 2.577 (2.407–2.735) | 2.459 (2.322–2.462) | 0.95 |
| D16 | generated lines | 2,493 | 2,493 | 1.00 |
| D16 | generate wall (s) | 0.627 (0.581–0.721) | 0.699 (0.645–0.748) | 1.11 |
| D16 | generate peak memory (MB) | 40.6 (40.5–40.7) | 40.7 (40.7–40.8) | 1.00 |
| D16 | compile -Onone (s) | 3.922 (3.920–4.071) | 3.988 (3.959–4.064) | 1.02 |
| D16 | compile -O (s) | 4.462 (4.231–4.816) | 4.264 (3.863–4.729) | 0.96 |
| D20 | generated lines | 5,229 | 5,229 | 1.00 |
| D20 | generate wall (s) | 1.124 (1.002–1.127) | 1.208 (1.156–1.490) | 1.07 |
| D20 | generate peak memory (MB) | 45.5 (45.4–46.2) | 46.2 (46.1–46.3) | 1.01 |
| D20 | compile -Onone (s) | 11.4 (10.3–11.5) | 12.0 (11.0–12.2) | 1.05 |
| D20 | compile -O (s) | 5.952 (5.330–6.043) | 5.656 (5.321–5.842) | 0.95 |
| D24 | did not build | main: App did not compile at -Onone: bol names (ensure you have llvm-symbolizer in your PATH or set the environment var `LLVM_ | | |
| D24 | did not build | slice2: App did not compile at -Onone: bol names (ensure you have llvm-symbolizer in your PATH or set the environment var `LLVM_ | | |

Where slice2 is slower than main (median ratio above 1), ranked:

| Ratio | Shape | Measure |
|---|---|---|
| 1.11 | D16 | generate wall (s) |
| 1.08 | D12 | generate wall (s) |
| 1.07 | D20 | generate wall (s) |
| 1.05 | D20 | compile -Onone (s) |
| 1.03 | D8 | compile -O (s) |
| 1.02 | D16 | compile -Onone (s) |
| 1.02 | D12 | generate peak memory (MB) |
| 1.01 | D20 | generate peak memory (MB) |
| 1.00 | D8 | generate peak memory (MB) |
| 1.00 | D16 | generate peak memory (MB) |
