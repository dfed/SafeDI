func benchmarkIteration() -> Int {
	withExtendedLifetime(Root.mock()) {}
	return 34
}
