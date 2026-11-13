
fixture300, combined, -j 4, clean: build wall 25.14s
| job | primaries (generated) | frontend wall s | type-check s | SILGen+SIL opt s | IRGen s | rest (LLVM codegen, object) s |
|---|---|---|---|---|---|---|
| emit-module | — | 2.54 | 2.05 | 0.34 | 0.00 | 0.14 |
| compile Feature048.swift … | 23 (0) | 0.67 | 0.23 | 0.06 | 0.05 | 0.34 |
| compile Feature024.swift … | 24 (0) | 0.79 | 0.30 | 0.07 | 0.05 | 0.38 |
| compile Feature000.swift … | 24 (0) | 0.77 | 0.27 | 0.06 | 0.07 | 0.36 |
| compile Feature071.swift … | 23 (0) | 0.57 | 0.23 | 0.04 | 0.04 | 0.26 |
| compile Feature094.swift … | 23 (0) | 0.54 | 0.20 | 0.04 | 0.03 | 0.26 |
| compile Feature117.swift … | 23 (0) | 0.57 | 0.20 | 0.05 | 0.04 | 0.28 |
| compile Feature140.swift … | 23 (0) | 0.55 | 0.21 | 0.05 | 0.04 | 0.26 |
| compile Feature186.swift … | 23 (0) | 0.56 | 0.19 | 0.04 | 0.04 | 0.29 |
| compile Feature163.swift … | 23 (0) | 0.57 | 0.21 | 0.05 | 0.04 | 0.28 |
| compile Feature209.swift … | 23 (0) | 0.55 | 0.17 | 0.05 | 0.04 | 0.29 |
| compile Feature232.swift … | 23 (0) | 0.54 | 0.18 | 0.05 | 0.04 | 0.27 |
| compile Feature255.swift … | 23 (0) | 0.50 | 0.18 | 0.04 | 0.03 | 0.25 |
| compile Service011.swift … | 23 (1) | 21.61 | 3.91 | 1.64 | 2.87 | 13.19 |
| **sum** | | **31.32** | **8.53** | **2.58** | **3.37** | **16.84** |

fixture300, combined, -j 4, private-method edit: build wall 13.66s
| job | primaries (generated) | frontend wall s | type-check s | SILGen+SIL opt s | IRGen s | rest (LLVM codegen, object) s |
|---|---|---|---|---|---|---|
| emit-module | — | 2.66 | 2.17 | 0.34 | 0.00 | 0.15 |
| compile Feature007.swift … | 1 (0) | 0.12 | 0.04 | 0.01 | 0.00 | 0.07 |
| compile SafeDIGenerated.swift … | 1 (1) | 10.53 | 3.74 | 1.31 | 2.55 | 2.92 |
| compile Feature006.swift … | 1 (0) | 0.15 | 0.06 | 0.01 | 0.00 | 0.09 |
| **sum** | | **13.46** | **6.01** | **1.67** | **2.55** | **3.23** |

fixture300, 8 mock files, -j 4, clean: build wall 23.80s
| job | primaries (generated) | frontend wall s | type-check s | SILGen+SIL opt s | IRGen s | rest (LLVM codegen, object) s |
|---|---|---|---|---|---|---|
| compile Feature048.swift … | 24 (0) | 0.67 | 0.22 | 0.06 | 0.05 | 0.34 |
| compile Feature000.swift … | 24 (0) | 0.69 | 0.27 | 0.06 | 0.04 | 0.31 |
| compile Feature024.swift … | 24 (0) | 0.56 | 0.20 | 0.05 | 0.04 | 0.28 |
| emit-module | — | 2.70 | 2.15 | 0.37 | 0.00 | 0.17 |
| compile Feature072.swift … | 24 (0) | 0.74 | 0.29 | 0.06 | 0.05 | 0.35 |
| compile Feature096.swift … | 24 (0) | 0.66 | 0.24 | 0.05 | 0.05 | 0.32 |
| compile Feature120.swift … | 24 (0) | 0.67 | 0.25 | 0.05 | 0.04 | 0.33 |
| compile Feature144.swift … | 24 (0) | 0.67 | 0.27 | 0.05 | 0.04 | 0.29 |
| compile Feature168.swift … | 24 (0) | 0.61 | 0.20 | 0.05 | 0.04 | 0.31 |
| compile Feature192.swift … | 24 (0) | 0.58 | 0.17 | 0.05 | 0.04 | 0.32 |
| compile Feature216.swift … | 24 (0) | 0.59 | 0.18 | 0.05 | 0.04 | 0.32 |
| compile Feature240.swift … | 23 (0) | 0.56 | 0.18 | 0.04 | 0.04 | 0.30 |
| compile Feature263.swift … | 23 (0) | 0.50 | 0.18 | 0.03 | 0.03 | 0.25 |
| compile Service019.swift … | 23 (9) | 20.67 | 3.70 | 1.48 | 2.92 | 12.57 |
| **sum** | | **30.85** | **8.51** | **2.46** | **3.41** | **16.46** |

fixture300, 8 mock files, -j 4, private-method edit: build wall 6.28s
| job | primaries (generated) | frontend wall s | type-check s | SILGen+SIL opt s | IRGen s | rest (LLVM codegen, object) s |
|---|---|---|---|---|---|---|
| emit-module | — | 2.45 | 1.97 | 0.35 | 0.00 | 0.13 |
| compile Feature007.swift … | 1 (0) | 0.11 | 0.04 | 0.01 | 0.00 | 0.06 |
| compile Feature006.swift … | 2 (1) | 1.19 | 0.54 | 0.13 | 0.28 | 0.24 |
| compile SafeDIGenerated.swift … | 1 (1) | 1.22 | 0.34 | 0.08 | 0.68 | 0.12 |
| compile SafeDIGenerated.mocks.3.swift … | 1 (1) | 3.46 | 0.97 | 0.25 | 1.58 | 0.66 |
| compile SafeDIGenerated.mocks.1.swift … | 1 (1) | 1.84 | 0.62 | 0.18 | 0.67 | 0.37 |
| **sum** | | **10.26** | **4.48** | **1.00** | **3.21** | **1.58** |

fixture300, 64 mock files, -j 4, clean: build wall 12.32s
| job | primaries (generated) | frontend wall s | type-check s | SILGen+SIL opt s | IRGen s | rest (LLVM codegen, object) s |
|---|---|---|---|---|---|---|
| compile Feature025.swift … | 25 (0) | 0.63 | 0.29 | 0.05 | 0.04 | 0.25 |
| compile Feature000.swift … | 25 (0) | 0.69 | 0.27 | 0.06 | 0.04 | 0.32 |
| compile Feature050.swift … | 25 (0) | 0.64 | 0.25 | 0.05 | 0.04 | 0.29 |
| emit-module | — | 2.36 | 1.94 | 0.28 | 0.00 | 0.15 |
| compile Feature075.swift … | 25 (0) | 0.63 | 0.18 | 0.06 | 0.05 | 0.34 |
| compile Feature100.swift … | 25 (0) | 0.58 | 0.20 | 0.05 | 0.04 | 0.29 |
| compile Feature149.swift … | 24 (0) | 0.51 | 0.17 | 0.05 | 0.04 | 0.26 |
| compile Feature125.swift … | 24 (0) | 0.64 | 0.24 | 0.05 | 0.04 | 0.30 |
| compile Feature173.swift … | 24 (0) | 0.55 | 0.18 | 0.05 | 0.04 | 0.28 |
| compile Feature197.swift … | 24 (0) | 0.55 | 0.19 | 0.05 | 0.04 | 0.27 |
| compile Feature221.swift … | 24 (0) | 0.46 | 0.14 | 0.04 | 0.03 | 0.25 |
| compile Feature245.swift … | 24 (0) | 0.56 | 0.19 | 0.05 | 0.04 | 0.28 |
| compile Service002.swift … | 24 (0) | 0.38 | 0.12 | 0.03 | 0.03 | 0.20 |
| compile Utility005.swift … | 24 (17) | 5.70 | 1.06 | 0.39 | 1.19 | 3.06 |
| compile SafeDIGenerated.mocks.24.swift … | 24 (24) | 9.08 | 1.70 | 0.55 | 1.69 | 5.15 |
| compile SafeDIGenerated.mocks.46.swift … | 24 (24) | 7.96 | 1.50 | 0.63 | 1.58 | 4.25 |
| **sum** | | **31.92** | **8.61** | **2.43** | **4.94** | **15.94** |

fixture300, 64 mock files, -j 4, private-method edit: build wall 6.18s
| job | primaries (generated) | frontend wall s | type-check s | SILGen+SIL opt s | IRGen s | rest (LLVM codegen, object) s |
|---|---|---|---|---|---|---|
| emit-module | — | 2.44 | 2.01 | 0.29 | 0.00 | 0.14 |
| compile Feature007.swift … | 1 (0) | 0.12 | 0.04 | 0.01 | 0.00 | 0.07 |
| compile SafeDIGenerated.swift … | 1 (1) | 1.73 | 0.40 | 0.08 | 1.12 | 0.13 |
| compile SafeDIGenerated.mocks.43.swift … | 2 (2) | 3.27 | 0.89 | 0.21 | 1.53 | 0.63 |
| compile Feature006.swift … | 2 (1) | 0.30 | 0.10 | 0.02 | 0.09 | 0.09 |
| compile SafeDIGenerated.mocks.59.swift … | 1 (1) | 0.43 | 0.14 | 0.03 | 0.16 | 0.10 |
| **sum** | | **8.27** | **3.57** | **0.63** | **2.90** | **1.16** |
