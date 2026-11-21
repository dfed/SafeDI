import SafeDI

// “Cross-module mock generation”: a mock of a type module `Core` declares, generated in this module.
#SafeDIConfiguration(additionalMocksToGenerate: ["Database"])
